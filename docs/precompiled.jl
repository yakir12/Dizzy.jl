# ## Precompiled system image
#
# To eliminate startup latency, you can build a precompiled system image with [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl). The `docs/precompiled.jl` script exercises the package so the compiler can record what to precompile. Run this once (with the Arduino connected):
#
# ```julia
# using PackageCompiler
# PackageCompiler.create_sysimage(
#     ["Dizzy"];
#     sysimage_path = "DizzyPrecompiled.so",
#     precompile_execution_file = "docs/precompiled.jl"
# )
# ```
#
# Then start Julia with the image:
#
# ```
# julia --project=. -JDizzyPrecompiled.so
# ```


using Dizzy

file = joinpath(@__DIR__, "setups.json")

setups, available_setups = Dizzy.file2setups(file)

Dizzy.open_correct_arduino()
session = Dizzy.Session(setups['0'])
println("ready…")
haskey(setups, '1')
haskey(setups, 't')
for c in keys(setups)
    global session
    session = Dizzy.switch(session, setups[c])
    sleep(0.1)
end
Threads.@spawn Dizzy.beep(1)
Threads.@spawn Dizzy.beep(9)

Dizzy.off(session)
Dizzy.close_sp!()
