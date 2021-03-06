

# NOTE:  these are several hacks to make the forward declarations work
# this side steps dispatching when making ccalls with Ptr{Abstract} using a Ref{Concrete<:Abstract}
struct _Ref{To, From, R<:Base.RefValue{From}}
	r::R
end
Base.cconvert(::Type{Ptr{CO}}, r::R) where {CO<:Copaques, R<:Base.RefValue{CO}} = r
Base.cconvert(::Type{Ptr{CO}}, r::R) where {CO<:Copaques, T<:CO, R<:Base.RefValue{T}} = _Ref{CO, T, R}(r)
Base.unsafe_convert(::Type{Ptr{CO}}, r::_Ref{CO, T, R}) where {CO<:Copaques, T<:CO, R<:Base.RefValue{T}} = reinterpret(Ptr{CO}, Base.unsafe_convert(Ptr{T}, r.r))
Base.unsafe_load(p::Ptr{CO}, i::Integer = 1) where {CO<:Copaques} = Base.pointerref(reinterpret(Ptr{concrete(CO)}, p), Int(i), 1)
Base.unsafe_store!(p::Ptr{CO}, x, i::Integer = 1) where {CO<:Copaques} = Base.pointerset(reinterpret(Ptr{concrete(CO)}, p), convert(concrete(CO), x), Int(i), 1)



function _dlsym(sym::Symbol, libs::Clibrary...)
	for (ind, lib) in enumerate(libs)
		isLast = ind == length(libs)
		if VERSION >= v"1.1-"
			handle = Libdl.dlsym(lib.handle, sym, throw_error = isLast)
			(nothing === handle) || return handle
		else
			handle = (isLast ? Libdl.dlsym : Libdl.dlsym_e)(lib.handle, sym)
			(C_NULL == handle) || return handle
		end
	end
	error("Libdl.dlsym returned a C_NULL handle and did not throw an error")
end



const _alignExprs = (Symbol("@calign"), Expr(:., Symbol("𝐣𝐥"), QuoteNode(Symbol("@calign"))))
const _enumExprs = (Symbol("@cenum"), Expr(:., Symbol("𝐣𝐥"), QuoteNode(Symbol("@cenum"))))
const _arrayExprs = (Symbol("@carray"), Expr(:., Symbol("𝐣𝐥"), QuoteNode(Symbol("@carray"))))
const _structExprs = (Symbol("@cstruct"), Expr(:., Symbol("𝐣𝐥"), QuoteNode(Symbol("@cstruct"))))
const _unionExprs = (Symbol("@cunion"), Expr(:., Symbol("𝐣𝐥"), QuoteNode(Symbol("@cunion"))))
const _externExprs = (Symbol("@cextern"), Expr(:., Symbol("𝐣𝐥"), QuoteNode(Symbol("@cextern"))))

# macros need to accumulate definition of sub-structs/unions and define them above the expansion of the macro itself
_expand(mod::Module, deps::Vector{Pair{Symbol, Expr}}, x, escape::Bool = true) = x isa Symbol && x !== :_ && escape ? esc(x) : x
function _expand(mod::Module, deps::Vector{Pair{Symbol, Expr}}, e::Expr, escape::Bool = true)
	if Base.is_expr(e, :macrocall)
		if length(e.args) > 1 && e.args[1] in (_alignExprs..., _enumExprs..., _arrayExprs..., _structExprs..., _unionExprs...)
			if e.args[1] in _alignExprs
				return _calign(mod, deps, filter(x -> !(x isa LineNumberNode), e.args[2:end])...)
			elseif e.args[1] in _enumExprs
				return _cenum(mod, deps, filter(x -> !(x isa LineNumberNode), e.args[2:end])...)
			elseif e.args[1] in _arrayExprs
				return _carray(mod, deps, filter(x -> !(x isa LineNumberNode), e.args[2:end])...)
			elseif e.args[1] in _structExprs
				return _caggregate(mod, deps, :cstruct, filter(x -> !(x isa LineNumberNode), e.args[2:end])...)
			elseif e.args[1] in _unionExprs
				return _caggregate(mod, deps, :cunion, filter(x -> !(x isa LineNumberNode), e.args[2:end])...)
			end
		else
			return _expand(mod, deps, macroexpand(mod, e, recursive = false), escape)
		end
	elseif Base.is_expr(e, :ref)
		return _carray(mod, deps, e)
	elseif Base.is_expr(e, :escape)
		return e
	else
		for i in eachindex(e.args)
			e.args[i] = _expand(mod, deps, e.args[i], escape)
		end
		return e
	end
end



function _augment(aug, augType)
	_recurse(args, ind) = args[ind] === :_ ? (args[ind] = deepcopy(augType)) : _augment(args[ind], augType)
	
	if !(aug isa Expr) || Base.is_expr(aug, :.) || Base.is_expr(aug, :block) || Base.is_expr(aug, :bracescat) || Base.is_expr(aug, :braces)
	elseif Base.is_expr(aug, :macrocall)
		foreach(i -> _recurse(aug.args, i), 2:length(aug.args))
	elseif Base.is_expr(aug, :call)
		foreach(i -> _recurse(aug.args, i), 2:length(aug.args))
	elseif Base.is_expr(aug, :escape, 1)
		_recurse(aug.args, 1)
	elseif Base.is_expr(aug, :ref) && length(aug.args) >= 1
		foreach(i -> _recurse(aug.args, i), 1:length(aug.args))
	elseif Base.is_expr(aug, :..., 1)
		_recurse(aug.args, 1)
	elseif Base.is_expr(aug, :(::), 2)
		_recurse(aug.args, 2)
	elseif Base.is_expr(aug, :curly) && length(aug.args) >= 1
		foreach(i -> _recurse(aug.args, i), 1:length(aug.args))
	else
		error("Expected augmented expression to have a `varName`, `varName::_`, `varName::Ptr{_}`, `varName::_[N]`, or `funcName(arg::ArgType)::Ptr{_}` expression or some combination of them, but found `$(aug)`")
	end
end



macro calign(exprs...) return _calign(__module__, nothing, exprs...) end

function _calign(mod::Module, deps::Union{Vector{Pair{Symbol, Expr}}, Nothing}, expr::Union{Integer, Expr})
	isOuter = (nothing === deps)
	deps = isOuter ? Pair{Symbol, Expr}[] : deps
	def = Expr(:align, _expand(mod, deps, expr))
	
	return isOuter ? quote $(map(last, deps)...) ; $(def) end : def
end



macro ctypedef(exprs...) return _ctypedef(__module__, nothing, exprs...) end

function _ctypedef(mod::Module, deps::Union{Vector{Pair{Symbol, Expr}}, Nothing}, name::Symbol, expr::Union{Symbol, Expr})
	escName = esc(name)
	
	if Base.is_expr(expr, :macrocall) && length(expr.args) >= 3 && expr.args[1] in (_structExprs..., _unionExprs..., _enumExprs...)
		# ignore the typedef if the typedef name is identical to the struct/union/enum name
		name === expr.args[3] && return esc(expr)
		
		# propagate typedef name into anonymous types
		if Base.is_expr(expr.args[3], :braces) || Base.is_expr(expr.args[3], :bracescat)
			insert!(expr.args, 3, Expr(:tuple, name))
		end
	end
	
	isOuter = (nothing === deps)
	deps = isOuter ? Pair{Symbol, Expr}[] : deps
	expr = _expand(mod, deps, expr)
	push!(deps, name => quote
		const $(escName) = $(expr)
	end)
	
	return isOuter ? quote $(map(last, deps)...) ; $(escName) end : escName
end



