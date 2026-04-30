module Dizzy

using StructUtils
using JSON
using JSONSchema
using Distributions
using LibSerialPort
using COBSReduced
using Dates
using BeepBeep
using IterTools

export load_start

const ARDUINO_ID = UInt8[151, 152, 146, 82, 39, 59, 146, 254]

const NLEDS = 198

const schema = Schema(read(joinpath(@__DIR__, "schema.json"), String))

const sp = Ref{SerialPort}()

function close_sp!()
    isassigned(sp) && isopen(sp[]) && close(sp[])
end

function open_correct_arduino()
    sp_names = get_port_list()
    if isempty(sp_names)
        error("no serial ports found, make sure the USB is plugged in.")
    end
    for sp_name in sp_names
        temp_sp = open(sp_name, 115200)
        write(temp_sp, cobs_encode(UInt8[1]))
        sleep(0.1)
        msg = read(temp_sp)
        if !isempty(msg)
            id = cobs_decode(msg)
            if id == ARDUINO_ID
                sp[] = temp_sp
                return nothing
            end
        end
        close(temp_sp)
        @info "Tried $sp_name... It wasn't the Dizzy arduino."
    end
    error("the dizzy arduino is not plugged in")
end


mutable struct Sun
    azimuth::UInt8
    intensity::UInt8
end

function suns2msg(suns::Vector{Sun})
    foldl((msg, s) -> UInt8[s.azimuth; s.intensity; msg], sun for sun in suns if sun.intensity > 0, init = UInt8[])
end

@defaults struct JSUN
    mu::Float64
    green::UInt8 = 0xff
    int_delay::Float64 = 0.0 
    int_interval::Float64 = Inf
    kappa::Float64 = Inf
    az_delay::Float64 = 0.0 
    az_interval::Float64 = Inf
end

@defaults struct Setup
    name::String
    suns::Vector{JSUN}
end

abstract type Operation end

struct Intensity <: Operation
    green::UInt8
    index::Int
end

struct Azimuth <: Operation
    dist::VonMises{Float64}
    index::Int
    function Azimuth(μ, κ, index)
        new(VonMises(μ, κ), index)
    end
end

function update!(suns, op::Azimuth)
    suns[op.index].azimuth = α2index(rand(op.dist))
end

function update!(suns, op::Intensity)
    suns[op.index].intensity ⊻= op.green
end

struct Session
    task::Task
    running::Ref{Bool}
end

function Session(setup::Setup)
    jsuns = setup.suns
    suns = [Sun(α2index(deg2rad(jsun.mu)), jsun.green) for jsun in jsuns]
    running = Ref(true)
    task = Threads.@spawn begin
        last_t = 0.0
        dt = round(now(), Second(1))
        open("$dt $(setup.name).log", "w") do io
            println(io, "datetime,id,azimuth,intensity")
            write(sp[], cobs_encode(suns2msg(suns)))
            log!(io, suns)
            if !all(s -> isinf(s.az_interval) && isinf(s.int_interval) && isinf(s.kappa), jsuns)
                gm = gridded_merge_int(jsuns)
                for (t, operations) in gm
                    Threads.@spawn light(operations, suns, io, running)
                    sleep(t - last_t)
                    last_t = t
                    running[] || break
                end
            end
        end
    end
    return Session(task, running)
end

function switch(session, setup)
    off(session)
    println("setup $(setup.name) is on")
    Session(setup)
end

function off(session)
    session.running[] = false
    wait(session.task)
    sp_drain(sp[])
    write(sp[], cobs_encode(UInt8[]))
end


function gridded_merge_int(αs::AbstractVector{<:Integer}, δs::AbstractVector{<:Integer}, operations::AbstractVector{<:Operation})
    streams = [Iterators.Stateful(Iterators.countfrom(α, δ)) for (α, δ) in zip(αs, δs)]
    repeatedly() do
        cells = [peek(s) for s in streams]
        m_min = minimum(cells)
        idxs  = findall(==(m_min), cells)
        for i in idxs; popfirst!(streams[i]); end
        (m_min/1000, operations[idxs])
    end
end

fs2im(s::Real) = Int(1000s)

function gridded_merge_int(jsuns::AbstractVector{JSUN})
    starts = vcat([fs2im(jsun.az_delay) for jsun in jsuns if !isinf(jsun.az_interval)],
                  [fs2im(jsun.int_delay) for jsun in jsuns if !isinf(jsun.int_interval)])
    steps = vcat([fs2im(jsun.az_interval) for jsun in jsuns if !isinf(jsun.az_interval)],
                 [fs2im(jsun.int_interval) for jsun in jsuns if !isinf(jsun.int_interval)])
    operations = vcat([Azimuth(deg2rad(jsun.mu), jsun.kappa, i) for (i, jsun) in enumerate(jsuns) if !isinf(jsun.kappa)], 
                      [Intensity(jsun.green, i) for (i, jsun) in enumerate(jsuns) if !isinf(jsun.int_interval)])
    gridded_merge_int(starts, steps, operations)
end

α2index(α) = round(UInt8, clamp(NLEDS*(rem(α + π + π/2, 2π)/2π) - 0.5, 0, NLEDS - 1))
# α2index(α) = round(UInt8, clamp(NLEDS*((α + π)/2π) - 0.5, 0, NLEDS - 1))

index2α(i) = rad2deg(rem2pi(2π*(i + 0.5)/NLEDS - (π + π/2), RoundNearest))
# index2α(i) = 360*(i + 0.5)/NLEDS - 180


function readkey()
    ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, true)  # raw mode on
    try
        return read(stdin, Char)
    finally
        ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, false)  # raw mode off
    end
end

function log!(io, suns)
    dt = now()
    for (id, sun) in enumerate(suns)
        println(io, dt, ",", id, ",", index2α(sun.azimuth), ",", sun.intensity) 
    end
end

function light(operations, suns, io, running)
    for operation in operations
        update!(suns, operation)
    end
    write(sp[], cobs_encode(suns2msg(suns)))
    log!(io, suns)
    if !running[]
        sp_drain(sp[])
        write(sp[], cobs_encode(UInt8[]))
    end
end

function file2setups(file)
    pre_setups = JSON.parsefile(file)
    res = JSONSchema.validate(schema, pre_setups)
    if !isnothing(res)
        error(res)
    end
    setups = Dict(zip('1':'9', StructUtils.make(Vector{Setup}, pre_setups)))
    available_setups = ["$k: $(setup.name)" for (k, setup) in setups]
    sort!(available_setups, by = first)

    setups['0'] = Setup("off", [JSUN(index2α(i - 1), 0x00) for i in 1:NLEDS])
    setups['s'] = Setup("sync", [JSUN(index2α(i - 1), 0xff, 0, 1) for i in 1:NLEDS])
    setups['r'] = Setup("rand", [JSUN(rand(-180:180), rand(UInt8), max.(round.(rand(5), digits=2), 0.01)...) for _ in 1:NLEDS])

    return setups, available_setups
end

function load_start(file = joinpath(homedir(), "setups.json"); sound = false)
    setups, available_setups = file2setups(file)
    open_correct_arduino()
    println("ready…")
    session = Session(setups['0'])
    while true
        c = readkey()
        if haskey(setups, c)
            session = switch(session, setups[c])
            sound && Threads.@spawn beep(1)
        elseif c == 'q'
            switch(session, setups['0'])
            off(session)
            println("exiting")
            break
        else
            @warn """there is no setup for key "$c". Available setups are:""" available_setups
            sound && Threads.@spawn beep(9)
        end
    end
    close_sp!()
end


# function (@main)(ARGS)
#     file = length(ARGS) ≥ 1 ? ARGS[1] : joinpath(homedir(), "setups.json")
#     sound = length(ARGS) ≥ 2 ? parse(Bool, ARGS[2]) : false
#     load_start(file, sound)
#     return 0
# end

end
