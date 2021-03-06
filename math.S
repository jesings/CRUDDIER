.global crossproduct
.global dotproduct
.global normalize
.global deg2rad
.global cos2
.global sin2
.global exponent
.global illumination
.data
    pi: .double 3.141592658979
    ambient: .double 50, 50, 50, 0
    zeros: .double -0.0, -0.0, -0.0, -0.0
    twos: .double 2.0, 2.0, 2.0, 2.0
    viewvector: .double 0,0,1,0
.bss
.text
crossproduct://points packed in ymm0, ymm1
    vsubpd %ymm0, %ymm1, %ymm1//do cross product, find normal vector
    vsubpd %ymm0, %ymm2, %ymm2//do product of magnitudes of View vector ( <0,0,1> ) and normal vector
    vmovups %ymm1, %ymm0      //something
    vmovups %ymm2, %ymm1      //a2*b3-a3*b2,a3*b1-a1*b3,a1*b2-a2*b
    vpermq $0b11001001, %ymm0, %ymm2
    vpermq $0b11010010, %ymm1, %ymm3
    vmulpd %ymm2, %ymm3, %ymm2
    vpermq $0b11010010, %ymm0, %ymm3
    vpermq $0b11001001, %ymm1, %ymm4
    vmulpd %ymm3, %ymm4, %ymm3
    vsubpd %ymm3, %ymm2, %ymm0
    ret
dotproduct://stuff in ymm0, ymm1
    vmulpd %ymm0, %ymm1, %ymm0
    vpermq $0b00000010, %ymm0, %ymm1
    vhaddpd %ymm0, %ymm0, %ymm0
    vaddsd %xmm0, %xmm1, %xmm0
    ret
magnitude://stuff in ymm0
    vmulpd %ymm0, %ymm0, %ymm0
    vpermq $0b00000010, %ymm0, %ymm1
    vhaddpd %ymm0, %ymm0, %ymm0
    vaddsd %xmm0, %xmm1, %xmm0
    vsqrtsd %xmm0, %xmm0, %xmm0
    ret
normalize://stuff in ymm0
    sub $32, %rsp
    vmovupd %ymm0, (%rsp)
    call magnitude
    vpbroadcastq %xmm0, %ymm1
    vmovupd (%rsp), %ymm0
    vdivpd %ymm1, %ymm0, %ymm0
    add $32, %rsp
    ret
deg2rad://converts degrees to radians
    movsd pi(%rip), %xmm1
    mulsd %xmm1, %xmm0
    mov   $180, %rax
    cvtsi2sd %rax, %xmm1
    divsd %xmm1, %xmm0
    ret
.macro fputrig whichfunc, reg=0
    sub $8, %rsp
    vmovsd %xmm\reg, (%rsp)
    fldl (%rsp)
    f\whichfunc
    fstpl (%rsp)
    vmovsd  (%rsp), %xmm\reg
    add $8, %rsp
.endm
cos2:
    fputrig cos
    ret
sin2:
    fputrig sin
    ret
exponent://take xmm0 to the power of xmm1
    sub $8, %rsp
    vmovsd %xmm1, (%rsp)
    fldl (%rsp)
    vmovsd %xmm0, (%rsp)
    fldl (%rsp)
    fyl2x
    fld1
    fld %st(1)
    fprem
    f2xm1
    faddp
    fscale
    fstpl (%rsp)
    vmovsd (%rsp), %xmm0
    add $8, %rsp
    fstp %st(0)
    ret
.macro broadcastdotproduct arg1, arg2, result
    sub $64, %rsp
    vmovupd %ymm0, (%rsp)
    vmovupd %ymm1, 32(%rsp)
    vmovupd \arg1, %ymm0
    vmovupd \arg2, %ymm1

    vmulpd %ymm0, %ymm1, %ymm0
    vpermq $0b00000010, %ymm0, %ymm1
    vhaddpd %ymm0, %ymm0, %ymm0
    vaddsd %xmm0, %xmm1, %xmm0
    
    vpbroadcastq %xmm0, %ymm0
    vmovupd %ymm0, \result
    vmovupd 32(%rsp), %ymm1
    vmovupd (%rsp), %ymm0
    add $64, %rsp
.endm
.macro clamp regname
    mov $0xff, %rdi
    cmpq $0xff, %r\regname
    cmovg %rdi, %r\regname
    xor %rdi, %rdi
    cmpq $0, %r\regname
    cmovl %rdi, %r\regname
.endm
diffuse:
    vmulpd %ymm4, %ymm1, %ymm1
    broadcastdotproduct %ymm3, surfacenormal(%rip), %ymm5
    vmulpd %ymm1, %ymm5, %ymm1
    ret
//.endm
specular:
    vmulpd %ymm4, %ymm2, %ymm2
    vmulpd twos(%rip), %ymm5, %ymm5
    vmulpd surfacenormal(%rip), %ymm5, %ymm5
    vsubpd %ymm3, %ymm5, %ymm5
    broadcastdotproduct viewvector(%rip), %ymm5, %ymm5
    vcmppd $0x1D, zeros(%rip), %ymm5, %ymm6
    vandnpd %ymm5, %ymm6, %ymm5
    vmulpd %ymm5, %ymm5, %ymm5
    vmulpd %ymm5, %ymm5, %ymm5
    vmulpd %ymm5, %ymm2, %ymm2
    ret
illumination://Ka, Kd, Ks are in xmm 0, 1, 2, vector of light is in xmm3, color of light is in xmm4
    //Calculate ambient light
    sub $64, %rsp
    vmovupd %ymm0, (%rsp)
    vmovupd %ymm1, 32(%rsp)
    vmovupd %ymm3, %ymm0
    call normalize
    vmovupd %ymm0, %ymm3
    vmovupd (%rsp), %ymm0
    vmovupd 32(%rsp), %ymm1
    add $64, %rsp
    vmovupd ambient(%rip), %ymm5
    vmulpd %ymm5, %ymm0, %ymm0//this is the ambient light
    call diffuse//clamp
    call specular//clamp
    vcmppd $0x1D, zeros(%rip), %ymm1, %ymm6
    vandpd %ymm1, %ymm6, %ymm1
    vaddpd %ymm0, %ymm1, %ymm0
    vaddpd %ymm0, %ymm2, %ymm0
    call setcolor
    ret
setcolor://color packed in xmm0
    vcvtsd2si %xmm0, %rax
    vpermq $0b1001, %ymm0, %ymm0
    vcvtsd2si %xmm0, %rcx
    vpermq $0b01, %ymm0, %ymm0
    vcvtsd2si %xmm0, %rdx
    sub $8, %rsp
    movq $0, (%rsp)
    clamp ax
    clamp cx
    clamp dx
    mov %ax, (%rsp)
    mov %cx, 1(%rsp)
    mov %dx, 2(%rsp)
    mov (%rsp), %r15
    add $8, %rsp
    ret
