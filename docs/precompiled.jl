# # in a env that includes Dizzy (and PackageCompiler)
# using PackageCompiler
# PackageCompiler.create_sysimage(["Dizzy"]; sysimage_path="DizzyPrecompiled.so", precompile_execution_file="~/Dizzy/docs/precompiled.jl")
# then start julia like this:
# julia -JDizzyPrecompiled.so

using Dizzy

file = joinpath(@__DIR__, "setups.json")

setups, available_setups = Dizzy.file2setups(file)

Dizzy.open_sp!()
session = Dizzy.Session(setups['0'])
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
