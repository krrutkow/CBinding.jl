

@testset "@cunion" begin
	@eval @cunion OpaqueUnion
	@eval @cunion OpaqueUnion
	@test_throws ErrorException sizeof(OpaqueUnion)
	@test sizeof(Ptr{OpaqueUnion}) == sizeof(Ptr{Cvoid})
	
	@eval @cunion EmptyUnion {
	} __packed__
	@test sizeof(EmptyUnion) == 0
	
	@eval @cunion CcharUnion {
		c::Cchar
	} __packed__
	@test sizeof(CcharUnion) == sizeof(Cchar)
	@test :c in propertynames(CcharUnion)
	
	@eval @cunion CintUnion {
		i::Cint
	} __packed__
	@test sizeof(CintUnion) == sizeof(Cint)
	@test :i in propertynames(CintUnion)
	
	@eval @cunion CunionCintUnion {
		i::CintUnion
	} __packed__
	@test sizeof(CunionCintUnion) == sizeof(CintUnion)
	@test :i in propertynames(CunionCintUnion)
	
	@eval @cunion CintCcharUnion {
		i::CintUnion
		c::CcharUnion
	} __packed__
	@test sizeof(CintCcharUnion) == max(sizeof(CintUnion), sizeof(CcharUnion))
	@test :i in propertynames(CintCcharUnion)
	@test :c in propertynames(CintCcharUnion)
	
	@eval @cunion CcharCintPackedUnion {
		c::CcharUnion
		i::CintUnion
	} __packed__
	@test sizeof(CcharCintPackedUnion) == max(sizeof(CintUnion), sizeof(CcharUnion))
	@test :c in propertynames(CcharCintPackedUnion)
	@test :i in propertynames(CcharCintPackedUnion)
	
	@eval @cunion CcharCintAlignedUnion {
		c::CcharUnion
		@calign sizeof(CintUnion)
		i::CintUnion
	} __packed__
	@test sizeof(CcharCintAlignedUnion) == max(max(sizeof(CintUnion), sizeof(Cint)), max(sizeof(CcharUnion), sizeof(Cint)))
	@test :c in propertynames(CcharCintAlignedUnion)
	@test :i in propertynames(CcharCintAlignedUnion)
	
	@eval @cunion CunionUnion {
		@cunion {
			c::Cuchar[4]
			s::Cushort[2]
			i::Cuint
		} __packed__
	} __packed__
	@test :c in propertynames(CunionUnion)
	@test :s in propertynames(CunionUnion)
	@test :i in propertynames(CunionUnion)
	
	@eval @cunion PtrToUnionUnion
	@eval @cunion PtrToPtrToUnionUnion {
		p::Ptr{PtrToUnionUnion}
	} __packed__
	@eval @cunion PtrToUnionUnion {
		p::Ptr{PtrToUnionUnion}
	} __packed__
	@test sizeof(PtrToPtrToUnionUnion) == sizeof(Ptr)
	@test :p in propertynames(PtrToPtrToUnionUnion)
	@test sizeof(PtrToUnionUnion) == sizeof(Ptr)
	@test :p in propertynames(PtrToUnionUnion)
	
	cuu = CunionUnion(zero)
	@test cuu.i == 0
	@test cuu.c[1] == 0
	@test cuu.c[4] == 0
	@test cuu.s[1] == 0
	@test cuu.s[2] == 0
	cuu.i = 0xff0000ff
	@test cuu.i == 0xff0000ff
	@test cuu.c[1] == 0xff
	@test cuu.c[4] == 0xff
	@test cuu.s[1] != 0
	@test cuu.s[2] != 0
	
	
	@eval @cunion Cint32BitfieldUnion {
		(i:32)::Cint
	} __packed__
	@test sizeof(Cint32BitfieldUnion) == sizeof(Cint)
	@test :i in propertynames(Cint32BitfieldUnion)
	
	@eval @cunion Cuint32BitfieldUnion {
		(u:32)::Cuint
	} __packed__
	@test sizeof(Cuint32BitfieldUnion) == sizeof(Cuint)
	@test :u in propertynames(Cuint32BitfieldUnion)
	
	@eval @cunion Cint2BitfieldUnion {
		(i:2)::Cint
	} __packed__
	@test sizeof(Cint2BitfieldUnion) == 1
	@test :i in propertynames(Cint2BitfieldUnion)
	
	@eval @cunion Cuint2BitfieldUnion {
		(u:2)::Cuint
	} __packed__
	@test sizeof(Cuint2BitfieldUnion) == 1
	@test :u in propertynames(Cuint2BitfieldUnion)
	
	@eval @cunion Cuint32Cint32BitfieldsUnion {
		(u:32)::Cuint
		(i:32)::Cint
	} __packed__
	@test sizeof(Cuint32Cint32BitfieldsUnion) == sizeof(Cuint)
	@test :u in propertynames(Cuint32Cint32BitfieldsUnion)
	@test :i in propertynames(Cuint32Cint32BitfieldsUnion)
	
	@eval @cunion Cuint16Cint16BitfieldsUnion {
		(u:16)::Cuint
		(i:16)::Cint
	} __packed__
	@test sizeof(Cuint16Cint16BitfieldsUnion) == 2
	@test :u in propertynames(Cuint16Cint16BitfieldsUnion)
	@test :i in propertynames(Cuint16Cint16BitfieldsUnion)
	
	@eval @cunion Cint16Cint16BitfieldsUnion {
		(i1:16)::Cint
		(i2:16)::Cint
	} __packed__
	@test sizeof(Cint16Cint16BitfieldsUnion) == 2
	
	@eval @cunion Cint16CalignCint16BitfieldsUnion {
		(i1:16)::Cint
		@calign sizeof(Cint)
		(i2:16)::Cint
	} __packed__
	@test sizeof(Cint16CalignCint16BitfieldsUnion) == sizeof(Cint)
	
	@eval @cunion Cint16CintBitfieldsUnion {
		(bf:16)::Cint
		i::Cint
	} __packed__
	@test sizeof(Cint16CintBitfieldsUnion) == sizeof(Cint)
	
	bfUnion = Cuint16Cint16BitfieldsUnion(zero)
	@test bfUnion.u == 0
	@test bfUnion.i == 0
	bfUnion.i = Cint(-1)
	@test bfUnion.u == 0xffff
	@test bfUnion.i == -1
	bfUnion.u = Cuint(0x0001)
	@test bfUnion.u == 0x0001
	@test bfUnion.i == 1
	
	bfUnion = Cint16CalignCint16BitfieldsUnion(zero)
	@test bfUnion.i1 == 0
	@test bfUnion.i2 == 0
	bfUnion.i1 = -1
	@test bfUnion.i1 == -1
	@test bfUnion.i2 == -1
	bfUnion.i2 = 0
	@test bfUnion.i1 == 0
	@test bfUnion.i2 == 0
	bfUnion.i2 = 32768
	@test bfUnion.i1 < 0
	@test bfUnion.i2 < 0
end

