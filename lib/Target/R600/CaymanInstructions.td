//===-- CaymanInstructions.td - CM Instruction defs  -------*- tablegen -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// TableGen definitions for instructions which are available only on Cayman
// family GPUs.
//
//===----------------------------------------------------------------------===//

def isCayman : Predicate<"Subtarget.hasCaymanISA()">;

//===----------------------------------------------------------------------===//
// Cayman Instructions
//===----------------------------------------------------------------------===//

let Predicates = [isCayman] in {

def MULADD_INT24_cm : R600_3OP <0x08, "MULADD_INT24",
  [(set i32:$dst, (add (mul I24:$src0, I24:$src1), i32:$src2))], VecALU
>;
def MUL_INT24_cm : R600_2OP <0x5B, "MUL_INT24",
  [(set i32:$dst, (mul I24:$src0, I24:$src1))], VecALU
>;

let isVector = 1 in {

def RECIP_IEEE_cm : RECIP_IEEE_Common<0x86>;

def MULLO_INT_cm : MULLO_INT_Common<0x8F>;
def MULHI_INT_cm : MULHI_INT_Common<0x90>;
def MULLO_UINT_cm : MULLO_UINT_Common<0x91>;
def MULHI_UINT_cm : MULHI_UINT_Common<0x92>;
def RECIPSQRT_CLAMPED_cm : RECIPSQRT_CLAMPED_Common<0x87>;
def EXP_IEEE_cm : EXP_IEEE_Common<0x81>;
def LOG_IEEE_cm : LOG_IEEE_Common<0x83>;
def RECIP_CLAMPED_cm : RECIP_CLAMPED_Common<0x84>;
def RECIPSQRT_IEEE_cm : RECIPSQRT_IEEE_Common<0x89>;
def SIN_cm : SIN_Common<0x8D>;
def COS_cm : COS_Common<0x8E>;
} // End isVector = 1

def : POW_Common <LOG_IEEE_cm, EXP_IEEE_cm, MUL>;

defm DIV_cm : DIV_Common<RECIP_IEEE_cm>;

// RECIP_UINT emulation for Cayman
// The multiplication scales from [0,1] to the unsigned integer range
def : Pat <
  (AMDGPUurecip i32:$src0),
  (FLT_TO_UINT_eg (MUL_IEEE (RECIP_IEEE_cm (UINT_TO_FLT_eg $src0)),
                            (MOV_IMM_I32 CONST.FP_UINT_MAX_PLUS_1)))
>;

  def CF_END_CM : CF_CLAUSE_EG<32, (ins), "CF_END"> {
    let ADDR = 0;
    let POP_COUNT = 0;
    let COUNT = 0;
  }


def : Pat<(fsqrt f32:$src), (MUL R600_Reg32:$src, (RECIPSQRT_CLAMPED_cm $src))>;

class RAT_STORE_DWORD <RegisterClass rc, ValueType vt, bits<4> mask> :
  CF_MEM_RAT_CACHELESS <0x14, 0, mask,
                        (ins rc:$rw_gpr, R600_TReg32_X:$index_gpr),
                        "STORE_DWORD $rw_gpr, $index_gpr",
                        [(global_store vt:$rw_gpr, i32:$index_gpr)]> {
  let eop = 0; // This bit is not used on Cayman.
}

def RAT_STORE_DWORD32 : RAT_STORE_DWORD <R600_TReg32_X, i32, 0x1>;
def RAT_STORE_DWORD64 : RAT_STORE_DWORD <R600_Reg64, v2i32, 0x3>;
def RAT_STORE_DWORD128 : RAT_STORE_DWORD <R600_Reg128, v4i32, 0xf>;

class VTX_READ_cm <string name, bits<8> buffer_id, dag outs, list<dag> pattern>
    : VTX_WORD0_cm, VTX_READ<name, buffer_id, outs, pattern> {

  // Static fields
  let VC_INST = 0;
  let FETCH_TYPE = 2;
  let FETCH_WHOLE_QUAD = 0;
  let BUFFER_ID = buffer_id;
  let SRC_REL = 0;
  // XXX: We can infer this field based on the SRC_GPR.  This would allow us
  // to store vertex addresses in any channel, not just X.
  let SRC_SEL_X = 0;
  let SRC_SEL_Y = 0;
  let STRUCTURED_READ = 0;
  let LDS_REQ = 0;
  let COALESCED_READ = 0;

  let Inst{31-0} = Word0;
}

class VTX_READ_8_cm <bits<8> buffer_id, list<dag> pattern>
    : VTX_READ_cm <"VTX_READ_8 $dst_gpr, $src_gpr", buffer_id,
                   (outs R600_TReg32_X:$dst_gpr), pattern> {

  let DST_SEL_X = 0;
  let DST_SEL_Y = 7;   // Masked
  let DST_SEL_Z = 7;   // Masked
  let DST_SEL_W = 7;   // Masked
  let DATA_FORMAT = 1; // FMT_8
}

class VTX_READ_16_cm <bits<8> buffer_id, list<dag> pattern>
    : VTX_READ_cm <"VTX_READ_16 $dst_gpr, $src_gpr", buffer_id,
                   (outs R600_TReg32_X:$dst_gpr), pattern> {
  let DST_SEL_X = 0;
  let DST_SEL_Y = 7;   // Masked
  let DST_SEL_Z = 7;   // Masked
  let DST_SEL_W = 7;   // Masked
  let DATA_FORMAT = 5; // FMT_16

}

class VTX_READ_32_cm <bits<8> buffer_id, list<dag> pattern>
    : VTX_READ_cm <"VTX_READ_32 $dst_gpr, $src_gpr", buffer_id,
                   (outs R600_TReg32_X:$dst_gpr), pattern> {

  let DST_SEL_X        = 0;
  let DST_SEL_Y        = 7;   // Masked
  let DST_SEL_Z        = 7;   // Masked
  let DST_SEL_W        = 7;   // Masked
  let DATA_FORMAT      = 0xD; // COLOR_32

  // This is not really necessary, but there were some GPU hangs that appeared
  // to be caused by ALU instructions in the next instruction group that wrote
  // to the $src_gpr registers of the VTX_READ.
  // e.g.
  // %T3_X<def> = VTX_READ_PARAM_32_eg %T2_X<kill>, 24
  // %T2_X<def> = MOV %ZERO
  //Adding this constraint prevents this from happening.
  let Constraints = "$src_gpr.ptr = $dst_gpr";
}

class VTX_READ_64_cm <bits<8> buffer_id, list<dag> pattern>
    : VTX_READ_cm <"VTX_READ_64 $dst_gpr, $src_gpr", buffer_id,
                   (outs R600_Reg64:$dst_gpr), pattern> {

  let DST_SEL_X        = 0;
  let DST_SEL_Y        = 1;
  let DST_SEL_Z        = 7;
  let DST_SEL_W        = 7;
  let DATA_FORMAT      = 0x1D; // COLOR_32_32
}

class VTX_READ_128_cm <bits<8> buffer_id, list<dag> pattern>
    : VTX_READ_cm <"VTX_READ_128 $dst_gpr.XYZW, $src_gpr", buffer_id,
                   (outs R600_Reg128:$dst_gpr), pattern> {

  let DST_SEL_X        =  0;
  let DST_SEL_Y        =  1;
  let DST_SEL_Z        =  2;
  let DST_SEL_W        =  3;
  let DATA_FORMAT      =  0x22; // COLOR_32_32_32_32

  // XXX: Need to force VTX_READ_128 instructions to write to the same register
  // that holds its buffer address to avoid potential hangs.  We can't use
  // the same constraint as VTX_READ_32_eg, because the $src_gpr.ptr and $dst
  // registers are different sizes.
}

//===----------------------------------------------------------------------===//
// VTX Read from parameter memory space
//===----------------------------------------------------------------------===//
def VTX_READ_PARAM_8_cm : VTX_READ_8_cm <0,
  [(set i32:$dst_gpr, (load_param_exti8 ADDRVTX_READ:$src_gpr))]
>;

def VTX_READ_PARAM_16_cm : VTX_READ_16_cm <0,
  [(set i32:$dst_gpr, (load_param_exti16 ADDRVTX_READ:$src_gpr))]
>;

def VTX_READ_PARAM_32_cm : VTX_READ_32_cm <0,
  [(set i32:$dst_gpr, (load_param ADDRVTX_READ:$src_gpr))]
>;

def VTX_READ_PARAM_64_cm : VTX_READ_64_cm <0,
  [(set v2i32:$dst_gpr, (load_param ADDRVTX_READ:$src_gpr))]
>;

def VTX_READ_PARAM_128_cm : VTX_READ_128_cm <0,
  [(set v4i32:$dst_gpr, (load_param ADDRVTX_READ:$src_gpr))]
>;

//===----------------------------------------------------------------------===//
// VTX Read from global memory space
//===----------------------------------------------------------------------===//

// 8-bit reads
def VTX_READ_GLOBAL_8_cm : VTX_READ_8_cm <1,
  [(set i32:$dst_gpr, (az_extloadi8_global ADDRVTX_READ:$src_gpr))]
>;

def VTX_READ_GLOBAL_16_cm : VTX_READ_16_cm <1,
  [(set i32:$dst_gpr, (az_extloadi16_global ADDRVTX_READ:$src_gpr))]
>;

// 32-bit reads
def VTX_READ_GLOBAL_32_cm : VTX_READ_32_cm <1,
  [(set i32:$dst_gpr, (global_load ADDRVTX_READ:$src_gpr))]
>;

// 64-bit reads
def VTX_READ_GLOBAL_64_cm : VTX_READ_64_cm <1,
  [(set v2i32:$dst_gpr, (global_load ADDRVTX_READ:$src_gpr))]
>;

// 128-bit reads
def VTX_READ_GLOBAL_128_cm : VTX_READ_128_cm <1,
  [(set v4i32:$dst_gpr, (global_load ADDRVTX_READ:$src_gpr))]
>;

} // End isCayman

