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

const NLEDS = 198

const schema = Schema(read(joinpath(@__DIR__, "schema.json"), String))

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
    suns[op.index][2] = α2index(rand(op.dist))
end

function update!(suns, op::Intensity)
    suns[op.index][3] ⊻= op.green
end

struct Session
    task::Task
    running::Ref{Bool}
end

function Session(setup::Setup)
    sp_name = get_sp_name()
    jsuns = setup.suns
    suns = [UInt8[i - 1, α2index(deg2rad(jsun.mu)), jsun.green] for (i, jsun) in enumerate(jsuns)]
    running = Ref(true)
    task = Threads.@spawn open(sp_name, 115200; mode = SP_MODE_WRITE) do sp
        write(sp, cobs_encode(vcat(suns...)))
        # sleep(1)
        last_t = 0.0
        dt = round(now(), Second(1))
        open("$dt $(setup.name).log", "w") do io
            println(io, "datetime,id,azimuth,intensity")
            if !all(s -> isinf(s.az_interval) && isinf(s.int_interval) && isinf(s.kappa), jsuns)
                gm = gridded_merge_int(jsuns)
                for (t, operations) in gm
                    Threads.@spawn light(operations, suns, sp, io)
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
    # Threads.@spawn beep(1)
    println("setup $(setup.name) is on")
    Session(setup)
end

function off(session)
    session.running[] = false
    wait(session.task)
    sp_name = get_sp_name()
    open(sp_name, 115200; mode = SP_MODE_WRITE) do sp
        msg = zeros(UInt8, 3NLEDS)
        msg[1:3:end] .= 0:NLEDS - 1
        write(sp, cobs_encode(msg))
    end
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

α2index(α) = round(UInt8, clamp(NLEDS*((α + π)/2π) - 0.5, 0, NLEDS - 1))

index2α(i) = 360*(i + 0.5)/NLEDS - 180


function readkey()
    ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, true)  # raw mode on
    try
        return read(stdin, Char)
    finally
        ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, false)  # raw mode off
    end
end

function light(operations, suns, sp, io)
    ids = Set{Int}()
    for operation in operations
        update!(suns, operation)
        push!(ids, operation.index)
    end
    msg = (suns[i] for i in ids)
    write(sp, cobs_encode(vcat(msg...)))
    dt = now()
    for (id, azimuth, intensity) in msg
        println(io, dt, ",", id + 1, ",", index2α(azimuth), ",", intensity) 
    end
end


function get_sp_name()
    sp_names = get_port_list()
    if isempty(sp_names)
        error("no serial ports found, make sure the USB is plugged in.")
    end
    last(sp_names)
end


function load_start(file = joinpath(homedir(), "setups.json"), beep = false)
    pre_setups = JSON.parsefile(file)
    res = JSONSchema.validate(schema, pre_setups)
    if !isnothing(res)
        println(res)
        return nothing
    end
    setups = Dict(zip('1':'9', StructUtils.make(Vector{Setup}, pre_setups)))
    available_setups = ["$k: $(setup.name)" for (k, setup) in setups]
    sort!(available_setups, by = first)

    setups['0'] = Setup("off", [JSUN(index2α(i - 1), 0x00) for i in 1:NLEDS])
    setups['s'] = Setup("sync", [JSUN(index2α(i - 1), 0xff, 0, 1) for i in 1:NLEDS])
    setups['r'] = Setup("rand", [JSUN(rand(-180:180), rand(UInt8), round.(max.(rand(5), 0.01), digits=2)...) for _ in 1:NLEDS])

    println("ready…")
    session = Session(setups['0'])
    while true
        c = readkey()
        if haskey(setups, c)
            session = switch(session, setups[c])
            beep && Threads.@spawn beep(1)
        elseif c == 'q'
            switch(session, setups['0'])
            off(session)
            println("exiting")
            break
        else
            @warn """there is no setup for key "$c". Available setups are:""" available_setups
            beep && Threads.@spawn beep(9)
        end
    end
end


# function (@main)(ARGS)
#     file = length(ARGS) ≥ 1 ? ARGS[1] : joinpath(homedir(), "setups.json")
#     beep = length(ARGS) ≥ 2 ? parse(Bool, ARGS[2]) : false
#     load_start(file, beep)
#     return 0
# end

end
