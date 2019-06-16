# CBinding.jl

This package provides improvements for specifying and using C bindings in Julia.
CBinding.jl has the goal of making it easier to correctly connect Julia to your C API and libraries.

# Usage

This package can be used to develop interfaces with C API's, but is best used by the [complementary automatic binding generation package](https://github.com/analytech-solutions/CBindingGen.jl).
CBinding.jl provides some missing functionality and more precise specification capabilities than the builtin Julia facilities for interfacing C provide.

## C Aggregate and Array Types

CBinding.jl provides a statically-sized C array similar to the static array constructs found in some other Julia packages.
An array definition is obtained by using the`@carray ElementType[SIZE]` syntax, which is provided to ease in the transcribing of C to Julia.
When used within the context of a `@cunion`, `@cstruct`, or `@ctypedef` macro, `ElementType[SIZE]` can be used directly to define arrays.

The `union` and `struct` aggregate types in C are described in very similar ways using CBinding.jl.
Both require the bit range of each aggregate field to be specified in order to support the different field packing approaches used in C.
Aggregate fields can be nested and anonymous aggregate fields can be used as well - two significant improvements over the usual Julian approach.

```jl
julia> using CBinding

julia> @cstruct MyFirstCStruct {
           i::Cint
       }
MyFirstCStruct

julia> @ctypedef MySecondType @cstruct MySecondCStruct {
           i::Cint
           j::Cint
           @cunion {
               w::Cuchar[sizeof(Cint)÷sizeof(Cuchar)]
               x::Cint
               y::(@cstruct {
                   c::Cuchar
               })[4]
               z::MyFirstCStruct[1]
           }
           m::MyFirstCStruct
       }
MySecondCStruct
```

As you can see, type definition syntax closely mimics that of C, which you should find helpful when transcribing more complicated types or API's with numerous types.
There are a few syntax differences to note though:

- a `@ctypedef` is specified with the type name before the definition rather than after (as is done in C)  
- likewise, an aggregate field is specified in the Julia `fieldName::FieldType` syntax rather than the C style of `FieldType fieldName`
- in C a single line can specified multiple types (like `SomeType a, *b, c[4]`), but with our syntax these all must be specified individually as `a::SomeType ; b::Ptr{SomeType} ; c::SomeType[4]`

There are a couple of ways to construct an aggregate type provided by the package.
Using the "default" constructor, or the `zero` function, will result in a zero-initialized object.
The "undef" constructor is also defined and does nothing to initialize the memory region of the allocated object, so it is optimal to use in situations where an object will be fully initialized with particular values.

```jl
julia> garbage = MySecondCStruct(undef)
MySecondCStruct(i=-340722048, j=32586, w=UInt8[0x00, 0x00, 0x00, 0x00], x=0, y=<anonymous-struct>[(c=0x00), (c=0x00), (c=0x00), (c=0x00)], z=MyFirstCStruct[(i=0)], m=MyFirstCStruct(i=0))

julia> zeroed = MySecondCStruct()
MySecondCStruct(i=0, j=0, w=UInt8[0x00, 0x00, 0x00, 0x00], x=0, y=<anonymous-struct>[(c=0x00), (c=0x00), (c=0x00), (c=0x00)], z=MyFirstCStruct[(i=0)], m=MyFirstCStruct(i=0))
```

Accessing the data fields within a C aggregate type works the way you would expect with one noteworthy detail.
Notice that when modifying fields within a union (e.g. `zeroed.y[3].c = 0xff`) the change is also observed in the other fields in the union (`zeroed.w`, `zeroed.x`, and `zeroed.y`).

```jl
julia> zeroed.i = 100
100

julia> zeroed
MySecondCStruct(i=100, j=0, w=UInt8[0x00, 0x00, 0x00, 0x00], x=0, y=<anonymous-struct>[(c=0x00), (c=0x00), (c=0x00), (c=0x00)], z=MyFirstCStruct[(i=0)], m=MyFirstCStruct(i=0))

julia> zeroed.y[3].c = 0xff
0xff

julia> zeroed
MySecondCStruct(i=100, j=0, w=UInt8[0x00, 0x00, 0xff, 0x00], x=16711680, y=<anonymous-struct>[(c=0x00), (c=0x00), (c=0xff), (c=0x00)], z=MyFirstCStruct[(i=16711680)], m=MyFirstCStruct(i=0))
```

When accessing a nested aggregate type, a `Caccessor` object is used to maintain a reference to the enclosing object.
To get the aggregate itself that a `Caccessor` is referring to you must use `[]` similar to Julia `Ref` usage.
This will lead to some surprising results/behavior if you forget this detail.
The implemented `Base.show` function will also cause the `Caccessor` to appear as if you are working with the aggregate, so trust `typeof`.

```jl
julia> typeof(zeroed.m)
Caccessor{MyFirstCStruct}

julia> typeof(zeroed.m[])
MyFirstCStruct

julia> sizeof(zeroed.m)
16

julia> sizeof(zeroed.m[])
4

julia> zeroed.m
MyFirstCStruct(i=0)

julia> zeroed.m = MyFirstCStruct(i = 42)
MyFirstCStruct(i=42)

julia> zeroed.m
MyFirstCStruct(i=42)

julia> zeroed.m[] = MyFirstCStruct(i = 0)
MyFirstCStruct(i=0)

julia> zeroed.m
MyFirstCStruct(i=0)
```

## C Field Alignment

By default, the fields in aggregates are packed, similar to using a `__attribute__((packed))` attribute in C, but usually C aggregate types have alignment requirements for their fields.
CBinding.jl features the `@calign` macro to describe these alignment requirements when defining aggregate types as well as padding the aggregate type itself to meet alignment requirements of its usage in arrays.

```jl
julia> @cstruct MyUnalignedCStruct {
           c::Cchar
           i::Cint
           @cunion {
               f::Cfloat
               d::Cdouble
           }
       }
MyUnalignedCStruct

julia> sizeof(MyUnalignedCStruct)
13

julia> @cstruct MyAlignedCStruct {
           @calign 1   # ensure alignment for next field at 1 byte
           c::Cchar
           @calign sizeof(Cint)   # ensure alignment for next field at 4 bytes
           i::Cint
           @calign sizeof(Cdouble)   # ensure alignment of largest nested field
           @cunion {
               @calign sizeof(Cfloat)
               f::Cfloat
               @calign sizeof(Cdouble)
               d::Cdouble
               @calign sizeof(Cdouble)
           }
           @calign sizeof(Cdouble)   # ensure alignment of sequentially allocated structs by aligning to the largest field alignment encountered in the struct
       }
MyAlignedCStruct

julia> sizeof(MyAlignedCStruct)
16
```

## C Bit Fields (coming soon)


## C Libraries

Interfacing C libraries is done through a `Clibrary` object.
Once the library object is available, it can be used for obtaining global variables or functions directly.
This approach allows for multiple libraries to be loaded without causing symbol conflicts.

```jl
julia> lib = Clibrary()  # dlopens the Julia process
Clibrary(Ptr{Nothing} @0x000061eefd6a1000)

julia> lib2 = Clibrary("/path/to/library.so")  # dlopens the library
Clibrary(Ptr{Nothing} @0x00006c1ce98c5000)
```

## C Global Variables (coming soon)


## C Functions

This package adds the ability to specify function pointers in a type-safe way to Julia, similar to how you would in C.
You may specify a `Cfunction` pointer directly, or use the constructor to load a symbol from a bound library.
The parametric types to `Cfunction` are used to specify the return type and the tuple of argument types for the function referenced.
The additional type-safety will help you avoid many mishaps when calling C functions.

```jl
julia> func = Cfunction{Clong, Tuple{Ptr{Clong}}}(lib, :time)
Ptr{Cfunction{Int64,Tuple{Ptr{Int64}}}} @0x0000652bdc514ea0

julia> @cstruct tm {
           sec::Cint
           min::Cint
           hour::Cint
           mday::Cint
           mon::Cint
           year::Cint
           wday::Cint
           yday::Cint
           isdst::Cint
       }
tm

julia> localtime = Cfunction{Ptr{tm}, Tuple{Ptr{Clong}}}(lib, :localtime)
Ptr{Cfunction{Ptr{tm},Tuple{Ptr{Int64}}}} @0x0000652bdb253fd0
```

CBinding.jl also makes a function pointer (`Ptr{<:Cfunction}`) callable.
So, just as you would in C, you can simply call the function pointer to invoke it.

```jl
julia> func(C_NULL)
1560708358

julia> t = Ref(Clong(0))
Base.RefValue{Int64}(0)

julia> func(t)
1560708359

julia> t[]
1560708359

julia> p = localtime(t)
Ptr{tm} @0x00007f4afa08b300

julia> unsafe_load(p)
tm(sec=59, min=5, hour=14, mday=16, mon=5, year=119, wday=0, yday=166, isdst=1)
```

Even interfacing the low-level C functions of Julia is simple!

```jl
julia> jl_gc_total_bytes = Cfunction{Clong, Tuple{}}(lib, :jl_gc_total_bytes)
Ptr{Cfunction{Int64,Tuple{}}} @0x00006f3e0c024bc0

julia> jl_gc_total_bytes()
160117962
```

## C Variadic Functions

Binding with a variadic function can be done using a `Vararg` argument type (which must be the last argument).
The variadic function calling capability provided with CBinding.jl is not limited in the ways that native Julia ccall usage is.
This enables Julia the ability to perform real-world variadic function usage as demonstrated with an example of binding to `printf` and then calling it below.

```jl
julia> func = Cfunction{Cvoid, Tuple{Cstring, Vararg}}(lib, :printf)
Ptr{Cfunction{Nothing,Tuple{Cstring,Vararg{Any,N} where N}}} @0x000061eefc388930

julia> func("%s i%c %ld great demo of CBinding.jl v%3.1lf%c\n", "this", 's', 1, 0.1, '!')
this is 1 great demo of CBinding.jl v0.1!
```