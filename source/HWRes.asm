; *** Resident part: Hardware dependent ***

include	NDISdef.inc
include	vt6105.inc
include	MIIdef.inc
include	misc.inc
include	DrvRes.inc

extern	DosIODelayCnt : far16

public	DrvMajVer, DrvMinVer
DrvMajVer	equ	1
DrvMinVer	equ	4

.386

_REGSTR	segment	use16 dword AT 'RGST'
	org	0
Reg	Rhine3_registers <>
_REGSTR	ends

_DATA	segment	public word use16 'DATA'

; --- DMA Descriptor management ---
public	VTxFreeCount, TxFreeCount
public	VTxHead, VTxFreeHead, TxFreeHead
VTxFreeCount	dw	0
TxFreeCount	dw	0
VTxHead		dw	0
VTxFreeHead	dw	0
TxFreeHead	dw	0

public	RxHead, RxTail, RxBusyHead, RxBusyTail, RxInProg
RxInProg	dw	0
RxHead		dw	0
RxTail		dw	0
RxBusyHead	dw	0
RxBusyTail	dw	0

; --- ReceiveChain Frame Descriptor ---
public	RxFrameLen, RxDesc	; << for debug info >>
RxFrameLen	dw	0
RxDesc		RxFrameDesc	<>


; --- Register Contents ---
public	regIntStatus, regIntMask	; << for debug info >>
regIntStatus	dw	0
regIntMask	dw	0
regMIISR	db	0
regGCR0		db	STOP

align	2
; --- Physical information ---
PhyInfo		_PhyInfo <>

public	MediaSpeed, MediaDuplex, MediaPause, MediaLink	; << for debug >>
MediaSpeed	db	0
MediaDuplex	db	0
MediaPause	db	0
MediaLink	db	0

; --- System(PCI) Resource ---
public	IOaddr, MEMSel, MEMaddr, IRQlevel
public	CacheLine, Latency, ChipRev
IOaddr		dw	?
MEMSel		dw	?
MEMaddr		dd	?
IRQlevel	db	?
CacheLine	db	?	; [0..3] <- [0,8,16,32]
Latency		db	?
ChipRev		db	?


; --- Configuration Memory Image Parameters ---
public	cfgSLOT, cfgTXQUEUE, cfgRXQUEUE, cfgMAXFRAMESIZE
public	cfgTxDRTH, cfgRxDRTH, cfgBCR0, cfgBCR1, cfgCFGB
public	cfgFCR1, cfgDAPOLL
cfgSLOT		db	0
cfgTXQUEUE	db	24
cfgRXQUEUE	db	32

cfgTxDRTH	db	TxThr_1024
cfgRxDRTH	db	RxThr_256

cfgBCR0		db	DMALen_64
cfgBCR1		db	6	; polling interval [0..7]
cfgCFGB		db	LATMEN

cfgFCR1		db	XLTH_4 or XHITH_24
cfgDAPOLL	db	1	; disable descriptor auto polling

cfgMAXFRAMESIZE	dw	1514

; --- Receive Buffer address ---
public	RxBufferLin, RxBufferPhys, RxBufferSize, RxBufferSelCnt, RxBufferSel
public	TxCopySel
RxBufferLin	dd	?
RxBufferPhys	dd	?
RxBufferSize	dd	?
RxBufferSelCnt	dw	?
TxCopySel	dw	?
RxBufferSel	dw	2 dup (?)	; max is 2.

; --- Vendor Adapter Description ---
public	AdapterDesc
AdapterDesc	db	'VIA VT6105 RhineIII Fast Ethernet Adapter',0


_DATA	ends

_TEXT	segment	public word use16 'CODE'
	assume	ds:_DATA, gs:_REGSTR
	
; USHORT hwTxChain(TxFrameDesc far *txd, USHORT rqh, USHORT pid)
_hwTxChain	proc	near
	push	bp
	mov	bp,sp
	push	fs
	lfs	bx,[bp+4]
	xor	ax,ax
	mov	dx,fs:[bx].TxFrameDesc.TxImmedLen
	mov	cx,fs:[bx].TxFrameDesc.TxDataCount
	cmp	ax,dx
	adc	ax,cx		; ax = number of TD required
	dec	cx
	jl	short loc_2	; immediate only
loc_1:
	add	dx,fs:[bx].TxFrameDesc.TxBufDesc1.TxDataLen
	add	bx,sizeof(TxBufDesc)
	dec	cx
	jge	short loc_1
loc_2:
	cmp	dx,[cfgMAXFRAMESIZE]	; dx = total length
	ja	short loc_ip		; invalid parameter
	cmp	dx,60			; pad required?
	ja	short loc_3
	mov	ax,1			; single fragment
loc_3:
	push	offset semTx
	call	_EnterCrit

	mov	si,[VTxFreeCount]
	mov	di,[TxFreeCount]
	dec	si			; vtxd available?
	jl	short loc_or
	sub	di,ax			; TD available?
	jge	short loc_4
loc_or:
	mov	ax,OUT_OF_RESOURCE
	jmp	near ptr loc_ex1
loc_ip:
	mov	ax,INVALID_PARAMETER
	jmp	near ptr loc_ex2

loc_4:
	mov	[VTxFreeCount],si
	mov	[TxFreeCount],di
	mov	bx,[VTxFreeHead]
	mov	di,[TxFreeHead]
	mov	cx,[bx].vtxd.vlnk
	mov	[bx].vtxd.head,di
	mov	[bx].vtxd.cnt,ax
	mov	[VTxFreeHead],cx	; update next vtxd
loc_5:
	mov	si,di
	dec	ax
	mov	di,[di].TD.vlnk
	jnz	short loc_5
	mov	[bx].vtxd.tail,si
	mov	[TxFreeHead],di		; update next TD

	mov	ax,[bp+8]
	mov	cx,[bp+10]
	mov	[bx].vtxd.reqhandle,ax
	mov	[bx].vtxd.protid,cx
	mov	bp,[bp+4]		; fs:bp = TxFrameDesc
	mov	cx,fs:[bp].TxFrameDesc.TxImmedLen
	test	cx,cx
	jz	short loc_6		; no immediate data

	push	cx		; copy immediate data
	push	ds
	push	ds
	pop	es
	lds	si,fs:[bp].TxFrameDesc.TxImmedPtr
	lea	di,[bx].vtxd.immed
	mov	ax,cx
	shr	cx,2
	and	ax,3
	rep	movsd
	mov	cx,ax
	rep	movsb
	pop	ds
	pop	cx

loc_6:
	cmp	dx,60			; pad required?
	jc	short loc_pad

loc_mul:
	mov	di,[bx].vtxd.head	; first fragment
	test	cx,cx
	jz	short loc_m1		; no immediate data
	mov	ax,word ptr [bx].vtxd.immedphys
	mov	dx,word ptr [bx].vtxd.immedphys[2]
	add	bp,offset TxFrameDesc.TxBufDesc1 - sizeof(TxBufDesc)
	jmp	short loc_m4

loc_m1:
	add	bp,offset TxFrameDesc.TxBufDesc1
loc_m2:
	cmp	fs:[bp].TxBufDesc.TxPtrType,0
	mov	ax,word ptr fs:[bp].TxBufDesc.TxDataPtr
	mov	dx,word ptr fs:[bp].TxBufDesc.TxDataPtr[2]
	jz	short loc_m3
	push	dx
	push	ax
	call	_VirtToPhys
	add	sp,4
loc_m3:
	mov	cx,fs:[bp].TxBufDesc.TxDataLen
loc_m4:
	or	cx,TxCHN		; chain
	mov	word ptr [di].TD.buf,ax
	mov	word ptr [di].TD.buf[2],dx
	mov	word ptr [di].TD.ctl,cx

	xor	ax,ax
	cmp	di,[bx].vtxd.head
	jnz	short loc_m5
	or	ax,highword(TxSTP)
loc_m5:
	cmp	di,[bx].vtxd.tail
	jz	short loc_m6		; end fragment

	mov	word ptr [di].TD.ctl[2],ax
;	mov	word ptr [di].TD.sts[2],highword(OWN)
	add	bp,sizeof(TxBufDesc)	; next fragment
	mov	di,[di].TD.vlnk
	jmp	short loc_m2

loc_m6:
	mov	si,[bx].vtxd.head
	or	ax,highword(TxEDP or IC)	; end, int
	mov	word ptr [di].TD.ctl[2],ax
	mov	word ptr [si].TD.sts[2],highword(OWN)
	jmp	short loc_rq

loc_pad:
	push	dx		; total size
	push	gs

	push	ds
	pop	es
	lea	di,[bx].vtxd.immed
	mov	dx,fs:[bp].TxFrameDesc.TxDataCount
	add	di,cx		; skip immediate data copied
loc_p1:
	dec	dx
	jl	short loc_p4	; no more fragment
	cmp	fs:[bp].TxFrameDesc.TxBufDesc1.TxPtrType,0
	mov	cx,fs:[bp].TxFrameDesc.TxBufDesc1.TxDataLen
	jnz	short loc_p2
	push	cx
	push	fs:[bp].TxFrameDesc.TxBufDesc1.TxDataPtr
	push	[TxCopySel]
	call	_PhysToGDT
	pop	gs		; refresh copy selector
	xor	si,si
	add	sp,4+2
	jmp	short loc_p3
loc_p2:
	lgs	si,fs:[bp].TxFrameDesc.TxBufDesc1.TxDataPtr
loc_p3:
	mov	ax,cx
	shr	cx,2
	and	ax,3
	rep	movsd	es:[di],gs:[si]
	mov	cx,ax
	rep	movsb	es:[di],gs:[si]
	add	bp,sizeof(TxBufDesc)
	jmp	short loc_p1

loc_p4:
	pop	gs
	pop	dx
	mov	cx,60
	sub	cx,dx
	mov	dx,cx
	and	cx,3
	shr	dx,2
	xor	eax,eax
	rep	stosb		; clear previous data
	mov	cx,dx
	rep	stosd

	mov	di,[bx].vtxd.head	; single fragment
	mov	eax,[bx].vtxd.immedphys
	mov	[di].TD.ctl, 60 or TxCHN or TxEDP or TxSTP or IC
	mov	[di].TD.buf,eax
	mov	word ptr [di].TD.sts[2],highword(OWN)

loc_rq:
	mov	al,[regGCR0]
	or	al,TxDMD
	mov	gs:[Reg.GCR0],al

	mov	ax,REQUEST_QUEUED
loc_ex1:
	call	_LeaveCrit
	pop	cx	; stack adjust
loc_ex2:
	pop	fs
	pop	bp
	retn
_hwTxChain	endp


_hwRxRelease	proc	near
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	offset semRx
	call	_EnterCrit

	mov	ax,[bp+4]		; ReqHandle = vrxd
	mov	bx,[RxInProg]
	test	bx,bx
	jz	short loc_1		; no frame in progress
	cmp	ax,bx
	jnz	short loc_1
	mov	[RxInProg],0
	jmp	short loc_4

loc_1:
	mov	bx,[RxBusyHead]
loc_2:
	or	bx,bx
	jz	short loc_6		; not found
	cmp	ax,bx
	jz	short loc_3		; found frame id matched
	mov	si,bx
	mov	bx,[bx].RD.blnk
	jmp	short loc_2
loc_3:
	mov	ax,[bx].RD.blnk
	cmp	bx,[RxBusyHead]
	jz	short loc_h
	cmp	bx,[RxBusyTail]
	jnz	short loc_m
loc_t:
	mov	[RxBusyTail],si
loc_m:
	mov	[si].RD.blnk,ax
	jmp	short loc_4
loc_h:
	mov	[RxBusyHead],ax

loc_4:
	mov	si,[RxTail]
	mov	di,[bx].RD.tail
	mov	eax,[bx].RD.phys
	mov	[si].RD.lnk,eax
	mov	[si].RD.vlnk,bx
	mov	[RxTail],di
	xor	ax,ax
loc_5:
;	mov	word ptr [si].RD.ctl,1535
;	mov	word ptr [si].RD.sts,RxCHN
	mov	word ptr [si].RD.sts[2],highword OWN
	mov	si,[si].RD.vlnk
	inc	ax
	cmp	si,di
	jnz	short loc_5

	mov	gs:[Reg.FCR0],al
;	mov	al,[regGCR0]
;	or	al,RxDMD
;	mov	gs:[Reg.GCR0],al
loc_6:
	call	_LeaveCrit
	pop	cx	; stack adjust
	mov	ax,SUCCESS
	pop	di
	pop	si
	pop	bp
	retn
_hwRxRelease	endp


_ServiceIntTx	proc	near
	push	offset semTx
loc_0:
	call	_EnterCrit
	mov	bx,[VTxHead]
	cmp	bx,[VTxFreeHead]
	jz	short loc_ex		; vtxd queue is empty
;	mov	si,[bx].vtxd.tail
	mov	si,[bx].vtxd.head
	mov	ax,word ptr [si].TD.sts[2]
	test	ax,highword OWN
	jnz	short loc_ex		; incomplete

	mov	cx,[bx].vtxd.cnt
	mov	dx,[bx].vtxd.vlnk
	inc	[VTxFreeCount]		; release vtxd
	add	[TxFreeCount],cx	; release TD
	mov	[VTxHead],dx		; update vtxd head
	mov	ax,word ptr [si].TD.sts
	mov	cx,[bx].vtxd.reqhandle
	mov	dx,[bx].vtxd.protid
	call	_LeaveCrit

	test	cx,cx
	jz	short loc_0		; null request handle - no confirm
	shr	ax,15
	mov	bx,[CommonChar.moduleID]
	mov	si,[ProtDS]
	neg	al			; [0,ff] <- TERR[0,1]

	push	dx	; ProtID
	push	bx	; MACID
	push	cx	; ReqHandle
	push	ax	; Status
	push	si	; ProtDS
;	cld
	call	dword ptr [LowDisp.txconfirm]
IF 1			; workarond for switch.os2 of Virtual PC
	mov	gs,[MEMSel]
ENDIF

	jmp	short loc_0

loc_ex:
	call	_LeaveCrit
	pop	ax	; stack adjust
	retn
_ServiceIntTx	endp


_ServiceIntRx	proc	near
	push	bp
	push	offset semRx
loc_0:
	call	_EnterCrit
loc_1:
	mov	bx,[RxInProg]
	mov	si,[RxHead]
	or	bx,bx
	jnz	near ptr loc_rty	; retry suspended frame
	cmp	si,[RxTail]
;	jz	short loc_ex		; rx queue unavailable!
	jz	near ptr loc_ex
	mov	ax,word ptr [si].RD.sts[2]
	test	ax,highword OWN
;	jnz	short loc_ex		; rx queue empty
	jnz	near ptr loc_ex
	mov	ax,word ptr [si].RD.sts
	test	ax,RxSTP
	jz	short loc_rmv		; first descriptor missing - discard
	mov	di,offset RxDesc.RxBufDesc1
	xor	bp,bp
;	mov	[RxDesc.RxDataCount],1
	mov	word ptr [di-2],1
loc_2:
	cmp	[RxDesc.RxDataCount],8
	ja	short loc_rmv		; too many fragment - discard
	mov	cx,word ptr [si].RD.vbuf
	mov	dx,word ptr [si].RD.vbuf[2]
	mov	word ptr [di].RxBufDesc.RxDataPtr,cx
	mov	word ptr [di].RxBufDesc.RxDataPtr[2],dx
	test	ax,RxEDP
	jnz	short loc_3		; last descriptor found
	mov	cx,word ptr [si].RD.ctl
	inc	[RxDesc.RxDataCount]
	mov	bx,si
	mov	[di].RxBufDesc.RxDataLen,cx
	mov	si,[si].RD.vlnk
	add	di,sizeof(RxBufDesc)
	add	bp,cx
	cmp	si,[RxTail]
	jz	short loc_ex		; rx queue full - remove? exit!
	mov	ax,word ptr [si].RD.sts[2]
	test	ax,highword OWN
	jnz	short loc_ex		; processing
	mov	dx,word ptr [si].RD.sts
	mov	ax,dx
	and	dx,RxSTP or RxEDP
	jz	short loc_rmv		; invalid setting
	cmp	dx,RxSTP or RxEDP
	jnz	short loc_2
				; single before last desc. - discard
	mov	si,bx		; previous pointer
	
loc_rmv:
;	mov	word ptr [si].RD.sts[2],0	; clear OWN - terminate
	mov	ax,[si].RD.vlnk
	mov	bx,[RxHead]
	mov	di,[RxTail]
	mov	[RxHead],ax
	mov	[RxTail],si
	mov	eax,[bx].RD.phys		; next link chain
	mov	[di].RD.lnk,eax
	mov	[di].RD.vlnk,bx
	xor	ax,ax
loc_rmv1:
;	mov	word ptr [di].RD.ctl,1536
;	mov	word ptr [di].RD.sts,RxCHN
	mov	word ptr [di].RD.sts[2],highword OWN
	mov	di,[di].RD.vlnk
	inc	ax
	cmp	si,di
	jnz	short loc_rmv1
	mov	gs:[Reg.FCR0],al		; update free RD count
;	mov	al,[regGCR0]
;	or	al,RxDMD
;	mov	gs:[Reg.GCR0],al		; poll demand
	jmp	near ptr loc_1

loc_ex:
	call	_LeaveCrit
	pop	cx	; stack adjust
	pop	bp
	retn

loc_3:
	test	ax,RXOK
	mov	dx,word ptr [si].RD.sts[2]
	jz	short loc_rmv		; errored frame - discard
	sub	dx,4			; frame length
	jna	short loc_rmv		; frame length <= 0?
	mov	ax,dx
	cmp	dx,[cfgMAXFRAMESIZE]
	ja	short loc_rmv		; too long length
	sub	dx,bp
	mov	[di].RxBufDesc.RxDataLen,dx
	ja	short loc_4
	dec	[RxDesc.RxDataCount]	; reduce fragment count
	jz	short loc_rmv
	add	[di-sizeof(RxBufDesc)].RxBufDesc.RxDataLen,dx
loc_4:
	mov	bx,[RxHead]
	mov	cx,[si].RD.vlnk
	mov	[RxFrameLen],ax
	mov	[bx].RD.tail,si
	mov	[RxInProg],bx
	mov	[RxHead],cx
loc_rty:
	call	_LeaveCrit

	call	_IndicationChkOFF
	or	ax,ax
	jz	short loc_spd		; indicate off - suspend...

	push	-1
	mov	bx,[RxInProg]
	mov	cx,[RxFrameLen]
	mov	ax,[ProtDS]
	mov	dx,[CommonChar.moduleID]
	mov	di,sp
	push	bx			; current RD = handle

	push	dx		; MACID
	push	cx		; FrameSize
	push	bx		; ReqHandle
	push	ds
	push	offset RxDesc	; RxFrameDesc
	push	ss
	push	di		; Indicate
	push	ax		; Protocol DS
;	cld
	call	dword ptr [LowDisp.rxchain]
IF 1			; workarond for switch.os2 of Virtual PC
	mov	gs,[MEMSel]
ENDIF
lock	or	[drvflags],mask df_idcp
	cmp	ax,WAIT_FOR_RELEASE
	jz	short loc_6
	call	_hwRxRelease
loc_5:
	pop	cx	; stack adjust
	pop	ax	; indicate
	cmp	al,-1
	jnz	short loc_spd		; indication remains OFF - suspend
	call	_IndicationON
	jmp	near ptr loc_0
loc_6:
	call	_RxPushBusyQueue
	jmp	short loc_5

loc_spd:
lock	or	[drvflags],mask df_rxsp
	pop	cx	; stack adjust
	pop	bp
	retn

_RxPushBusyQueue	proc	near
	push	offset semRx
	call	_EnterCrit
	mov	bx,[RxInProg]
	xor	ax,ax
	test	bx,bx
	jz	short loc_ex		; no progess frame
	mov	[bx].RD.blnk,ax		; null terminate
	mov	[RxInProg],ax		; clear In Progress state
	cmp	ax,[RxBusyHead]
	jnz	short loc_1
	mov	[RxBusyHead],bx
	jmp	short loc_2
loc_1:
	mov	si,[RxBusyTail]
	mov	[si].RD.blnk,bx
loc_2:
	mov	[RxBusyTail],bx
loc_ex:
	call	_LeaveCrit
	pop	bx	; stack adjust
	retn
_RxPushBusyQueue	endp

_ServiceIntRx	endp


_hwServiceInt	proc	near
	enter	2,0
loc_0:
	mov	ax,gs:[Reg.ISR]
lock	or	[regIntStatus],ax
	mov	ax,[regIntStatus]
	and	ax,[regIntMask]
	jz	short loc_4
	mov	gs:[Reg.ISR],ax

loc_1:
	mov	[bp-2],ax

	test	word ptr [bp-2],I_TX
	jz	short loc_2
lock	and	word ptr [regIntStatus],not(I_TX)
	call	_ServiceIntTx

loc_2:
	cmp	[Indication],0		; rx enable
	jnz	short loc_3
	test	word ptr [bp-2],I_RX
	jz	short loc_3
lock	and	word ptr [regIntStatus],not(I_RX)
	call	_ServiceIntRx

loc_3:
lock	btr	[drvflags],df_rxsp
	jnc	short loc_0
loc_4:
	leave
	retn
_hwServiceInt	endp

_hwCheckInt	proc	near
	mov	ax,gs:[Reg.ISR]
lock	or	[regIntStatus],ax
	mov	ax,[regIntStatus]
	test	ax,[regIntMask]
	setnz	al
	mov	ah,0
	retn
_hwCheckInt	endp

_hwEnableInt	proc	near
	mov	ax,[regIntMask]
	mov	gs:[Reg.IMR],ax		; set IMR
	retn
_hwEnableInt	endp

_hwDisableInt	proc	near
	mov	gs:[Reg.IMR],0		; clear IMR
;	mov	ax,gs:[Reg.IMR]		: dummy read
	retn
_hwDisableInt	endp

_hwIntReq	proc	near
		; do nothing... should I use software timer?
	retn
_hwIntReq	endp

_hwEnableRxInd	proc	near
	push	ax
lock	or	[regIntMask],I_RX
	cmp	[semInt],0
	jnz	short loc_1
	mov	ax,[regIntMask]
	mov	gs:[Reg.IMR],ax
loc_1:
	pop	ax
	retn
_hwEnableRxInd	endp

_hwDisableRxInd	proc	near
	push	ax
lock	and	[regIntMask],not(I_RX)
	cmp	[semInt],0
	jnz	short loc_1
	mov	ax,[regIntMask]
	mov	gs:[Reg.IMR],ax
loc_1:
	pop	ax
	retn
_hwDisableRxInd	endp


_hwPollLink	proc	near
;		--- MAUTO is not self-cleared by link-fail.
;	test	gs:[Reg.MII_CR],MAUTO	; auto polling running?
;	jz	short loc_0
;	retn
;		--- Check MIISR 
	mov	al,gs:[Reg.MII_SR]
	cmp	al,[regMIISR]
	jnz	short loc_0
	retn

loc_0:
IF 0		; --- don't read PHY's BMSR
	call	_ChkLink
	test	al,al
	mov	[MediaLink],al
	jnz	short loc_1	; Link active!?
	call	_ChkLink	; check again
	test	al,al
	mov	[MediaLink],al
	jnz	short loc_1	; Link active. short down?
	retn
ELSE		; --- check link fail for N-Way
	test	al,NWLINKF
	mov	[regMIISR],al
	jz	short loc_1
	retn
ENDIF

loc_1:
IF 0		; --- don't read PHY's ANLPAR
	call	_GetPhyMode
ELSE		; --- check speed,duplex,pause state for N-Way
	test	al,NWDPX
	mov	dl,0		; pause
	setnz	ah		; duplex
	jz	short loc_3
	test	al,NWSYM
	jz	short loc_2
	or	dl,3
loc_2:
	test	al,NWASYM
	jz	short loc_3
	or	dl,1
loc_3:
	test	al,MDSPD
	setz	al		; speed
ENDIF

	mov	MediaSpeed,al
	mov	MediaDuplex,ah
	mov	MediaPause,dl

	call	_SetMacEnv

	retn
_hwPollLink	endp

_hwOpen		proc	near	; call in protocol bind process?
	mov	al,START
	mov	[regGCR0],al
	mov	gs:[Reg.GCR0],al	; NIC start

	call	_SetDMAQueues
	call	_hwUpdatePktFlt

	call	_AutoNegotiate
	mov	MediaSpeed,al
	mov	MediaDuplex,ah
	mov	MediaPause,dl

	call	_SetMacEnv

	mov	[regMIISR],0		; check medium state in PollLink

	mov	ax,I_TX or I_RX
	mov	[regIntStatus],0
	mov	[regIntMask],ax
	mov	gs:[Reg.ISR],-1
	mov	gs:[Reg.MISR],-1
	mov	gs:[Reg.MIMR],0
	mov	gs:[Reg.IMR],ax

	mov	al,START or TxON or RxON
	mov	[regGCR0],al
	mov	gs:[Reg.GCR0],al

	mov	ax,SUCCESS
	retn
_hwOpen		endp

_SetMacEnv	proc	near
	mov	cl,gs:[Reg.GCR1]
	mov	al,[cfgFCR1]	; FCR1
	mov	ah,0		; MCR0
	and	cl,not FDX

	cmp	[MediaDuplex],0
	jz	short loc_2	; half duplex
	or	cl,FDX
	test	[MediaPause],1
	jz	short loc_1
	or	al,XONEN or FDXTFCEN	; tx pause enable
	or	ah,MFTXFEN
loc_1:
	test	[MediaPause],2
	jz	short loc_2
	or	al,FDXRFCEN		; rx pause enable
	or	ah,MFRXFEN
loc_2:
	mov	gs:[Reg.GCR1],cl
	mov	gs:[Reg.FCR1],al
	mov	gs:[Reg.MCR0],ah

	mov	gs:[Reg.MII_CR],MAUTO	; start auto polling

	call	_SetSpeedStat
	retn
_SetMacEnv	endp

_SetDMAQueues	proc	near
	push	offset semTx
loc_0:
	call	_EnterCrit
	mov	ax,[VTxHead]
	cmp	ax,[VTxFreeHead]
	jz	short loc_1		; no pending tx
	call	_LeaveCrit

	call	_ClearTx
	jmp	short loc_0

loc_1:
	mov	bx,[TxFreeHead]
	mov	ax,bx
	xor	cx,cx
loc_2:
	mov	word ptr [bx].TD.ctl,TxCHN
	mov	word ptr [bx].TD.sts[2],0	; clear OWN bit
	mov	bx,[bx].TD.vlnk
	inc	cx
	cmp	ax,bx
	jnz	short loc_2
	mov	[TxFreeCount],cx	; update free count
	mov	eax,[bx].TD.phys
	mov	gs:[Reg.TxDBA],eax	; tx descriptor base
	call	_LeaveCrit
	pop	cx	; stack adjust

	push	offset semRx
	call	_EnterCrit
	mov	bx,[RxHead]
	mov	ax,[RxTail]
	xor	cx,cx
	cmp	ax,bx
	jz	short loc_4		; no RD!?
loc_3:
;	mov	word ptr [bx].RD.ctl,1536
	mov	word ptr [bx].RD.sts,RxCHN
	mov	word ptr [bx].RD.sts[2],highword OWN
	mov	bx,[bx].RD.vlnk
	inc	cx
	cmp	ax,bx
	jnz	short loc_3
loc_4:
;	mov	word ptr [bx].RD.ctl,1536
	mov	word ptr [bx].RD.sts,RxCHN
	mov	word ptr [bx].RD.sts[2],0	; clear OWN, terminate
	mov	gs:[Reg.FCR0],cl	; update free rx count
	mov	bx,[RxHead]
	mov	eax,[bx].RD.phys
	mov	gs:[Reg.RxDBA],eax	; rx descriptor base
	call	_LeaveCrit
	pop	cx	; stack adjust
	retn
_SetDMAQueues	endp

_ClearTx	proc	near
	push	offset semTx
loc_0:
	call	_EnterCrit
	mov	bx,[VTxHead]
	cmp	bx,[VTxFreeHead]
	jnz	short loc_1
	call	_LeaveCrit
	pop	cx	; stack adjust
	retn

loc_1:
	mov	cx,[bx].vtxd.cnt
	mov	ax,[bx].vtxd.vlnk
	inc	[VTxFreeCount]
	add	[TxFreeCount],cx
	mov	[VTxHead],ax
	mov	cx,[bx].vtxd.reqhandle
	mov	dx,[bx].vtxd.protid
	call	_LeaveCrit

	test	cx,cx
	jz	short loc_0		; null request handle
	mov	bx,[CommonChar.moduleID]
	mov	ax,[ProtDS]

	push	dx	; ProtID
	push	bx	; MACID
	push	cx	; ReqHandle
	push	0ffh	; Status
	push	ax	; ProtDS
;	cld
	call	dword ptr [LowDisp.txconfirm]
IF 1			; workarond for switch.os2 of Virtual PC
	mov	gs,[MEMSel]
ENDIF

	jmp	short loc_0
_ClearTx	endp


_SetSpeedStat	proc	near
	mov	al,[MediaSpeed]
	mov	ah,0
	dec	ax
	jz	short loc_10M
	dec	ax
	jz	short loc_100M
;	dec	ax
;	jz	short loc_1G
	xor	ax,ax
	sub	cx,cx
	jmp	short loc_1
loc_10M:
	mov	cx,highword 10000000
	mov	ax,lowword  10000000
	jmp	short loc_1
loc_100M:
	mov	cx,highword 100000000
	mov	ax,lowword  100000000
;	jmp	short loc_1
loc_1G:
;	mov	cx,highword 1000000000
;	mov	ax,lowword  1000000000
loc_1:
	mov	word ptr [MacChar.linkspeed],ax
	mov	word ptr [MacChar.linkspeed][2],cx
	retn
_SetSpeedStat	endp


_ChkLink	proc	near
	push	miiBMSR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	and	ax,miiBMSR_LinkStat
	add	sp,2*2
	shr	ax,2
	retn
_ChkLink	endp


_AutoNegotiate	proc	near
	enter	2,0
	push	0
	push	miiBMCR
	push	[PhyInfo.Phyaddr]
	call	_miiWrite		; clear ANEnable bit
	add	sp,3*2

	push	33
	call	_Delay1ms
	push	miiBMCR_ANEnable or miiBMCR_RestartAN
;	push	miiBMCR_ANEnable	; remove restart bit??
	push	miiBMCR
	push	[PhyInfo.Phyaddr]
	call	_miiWrite		; restart Auto-Negotiation
	add	sp,(1+3)*2

	mov	word ptr [bp-2],12*30	; about 12sec.
loc_1:
	push	33
	call	_Delay1ms
	push	miiBMCR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,(1+2)*2
	test	ax,miiBMCR_RestartAN	; AN in progress?
	jz	short loc_2
	dec	word ptr [bp-2]
	jnz	short loc_1
	jmp	short loc_f
loc_2:
	push	33
	call	_Delay1ms
	push	miiBMSR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,(1+2)*2
	test	ax,miiBMSR_ANComp	; AN Base Page exchange complete?
	jnz	short loc_3
	dec	word ptr [bp-2]
	jnz	short loc_2
	jmp	short loc_f
loc_3:
	push	33
	call	_Delay1ms
	push	miiBMSR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,(1+2)*2
	test	ax,miiBMSR_LinkStat	; link establish?
	jnz	short loc_4
	dec	word ptr [bp-2]
	jnz	short loc_3
loc_f:
	xor	ax,ax			; AN failure.
	xor	dx,dx
	leave
	retn
loc_4:
	call	_GetPhyMode
	leave
	retn
_AutoNegotiate	endp

_GetPhyMode	proc	near
	push	miiANLPAR
	push	[PhyInfo.Phyaddr]
	call	_miiRead		; read base page
	add	sp,2*2
	mov	[PhyInfo.ANLPAR],ax

	test	[PhyInfo.BMSR],miiBMSR_ExtStat
	jz	short loc_2

	push	mii1KSTSR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,2*2
	mov	[PhyInfo.GSTSR],ax
;	shl	ax,2
;	and	ax,[PhyInfo.GSCR]
	shr	ax,2
	and	ax,[PhyInfo.GTCR]
;	test	ax,mii1KSCR_1KTFD
	test	ax,mii1KTCR_1KTFD
	jz	short loc_1
	mov	al,3			; media speed - 1000Mb
	mov	ah,1			; media duplex - full
	jmp	short loc_p
loc_1:
;	test	ax,mii1KSCR_1KTHD
	test	ax,mii1KTCR_1KTHD
	jz	short loc_2
	mov	al,3			; 1000Mb
	mov	ah,0			; half duplex
	jmp	short loc_p
loc_2:
	mov	ax,[PhyInfo.ANAR]
	and	ax,[PhyInfo.ANLPAR]
	test	ax,miiAN_100FD
	jz	short loc_3
	mov	al,2			; 100Mb
	mov	ah,1			; full duplex
	jmp	short loc_p
loc_3:
	test	ax,miiAN_100HD
	jz	short loc_4
	mov	al,2			; 100Mb
	mov	ah,0			; half duplex
	jmp	short loc_p
loc_4:
	test	ax,miiAN_10FD
	jz	short loc_5
	mov	al,1			; 10Mb
	mov	ah,1			; full duplex
	jmp	short loc_p
loc_5:
	test	ax,miiAN_10HD
	jz	short loc_e
	mov	al,1			; 10Mb
	mov	ah,0			; half duplex
	jmp	short loc_p
loc_e:
	xor	ax,ax
	sub	dx,dx
	retn
loc_p:
	cmp	ah,1			; full duplex?
	mov	dh,0
	jnz	short loc_np
	mov	cx,[PhyInfo.ANLPAR]
	test	cx,miiAN_PAUSE		; symmetry
	mov	dl,3			; tx/rx pause
	jnz	short loc_ex
	test	cx,miiAN_ASYPAUSE	; asymmetry
	mov	dl,2			; rx pause
	jnz	short loc_ex
loc_np:
	mov	dl,0			; no pause
loc_ex:
	retn
_GetPhyMode	endp


_ResetPhy	proc	near
	enter	2,0
	call	_miiReset	; Reset Interface
	push	miiPHYID2
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,2*2
	or	ax,ax		; ID2 = 0
	jz	short loc_1
	inc	ax		; ID2 = -1
	jnz	short loc_2
loc_1:
	mov	ax,HARDWARE_FAILURE
	leave
	retn

loc_2:
	push	miiPHYID1
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	mov	[PhyInfo.PHYID1],ax
	push	miiPHYID2
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	mov	[PhyInfo.PHYID1],ax
	add	sp,2*2*2

	push	miiBMCR_Reset
	push	miiBMCR
	push	[PhyInfo.Phyaddr]
	call	_miiWrite	; Reset PHY
	add	sp,3*2

	push	1536		; wait for about 1.5sec.
	call	_Delay1ms
	pop	ax

	call	_miiReset	; interface reset again
	mov	word ptr [bp-2],64  ; about 2sec.
loc_3:
	push	miiBMCR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,2*2
	test	ax,miiBMCR_Reset
	jz	short loc_4
	push	33
	call	_Delay1ms	; wait reset complete.
	pop	ax
	dec	word ptr [bp-2]
	jnz	short loc_3
	jmp	short loc_1	; PHY Reset Failure
loc_4:
	push	miiBMSR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,2*2
	mov	[PhyInfo.BMSR],ax
	push	miiANAR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,2*2
	mov	[PhyInfo.ANAR],ax
	test	[PhyInfo.BMSR],miiBMSR_ExtStat
	jz	short loc_5	; extended status exist?
	push	mii1KTCR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,2*2
	mov	[PhyInfo.GTCR],ax
	push	mii1KSCR
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	add	sp,2*2
	mov	[PhyInfo.GSCR],ax
	xor	cx,cx
	test	ax,mii1KSCR_1KTFD or mii1KSCR_1KXFD
	jz	short loc_41
	or	cx,mii1KTCR_1KTFD
loc_41:
	test	ax,mii1KSCR_1KTHD or mii1KSCR_1KXHD
	jz	short loc_42
	or	cx,mii1KTCR_1KTHD
loc_42:
	mov	ax,[PhyInfo.GTCR]
	and	ax,not (mii1KTCR_MSE or mii1KTCR_Port or \
		  mii1KTCR_1KTFD or mii1KTCR_1KTHD)
	or	ax,cx
	mov	[PhyInfo.GTCR],ax
	push	ax
	push	mii1KTCR
	push	[PhyInfo.Phyaddr]
	call	_miiWrite
	add	sp,2*2
loc_5:
	mov	ax,[PhyInfo.BMSR]
	mov	cx,miiAN_PAUSE
	test	ax,miiBMSR_100FD
	jz	short loc_61
	or	cx,miiAN_100FD
loc_61:
	test	ax,miiBMSR_100HD
	jz	short loc_62
	or	cx,miiAN_100HD
loc_62:
	test	ax,miiBMSR_10FD
	jz	short loc_63
	or	cx,miiAN_10FD
loc_63:
	test	ax,miiBMSR_10HD
	jz	short loc_64
	or	cx,miiAN_10HD
loc_64:
	mov	ax,[PhyInfo.ANAR]
	and	ax,not (miiAN_ASYPAUSE + miiAN_T4 + \
	  miiAN_100FD + miiAN_100HD + miiAN_10FD + miiAN_10HD)
	or	ax,cx
	mov	[PhyInfo.ANAR],ax
	push	ax
	push	miiANAR
	push	[PhyInfo.Phyaddr]
	call	_miiWrite
	add	sp,3*2

	call	_PhyWorkAround

	mov	ax,SUCCESS
	leave
	retn
_ResetPhy	endp

_PhyWorkAround	proc	near
	cmp	[PhyInfo.PHYID1],0101h
	jnz	short loc_ex
	mov	ax,[PhyInfo.PHYID2]
	mov	cx,ax
	shr	ax,4
	and	cl,0fh

	cmp	ax,8f4h		; VT6105
	jz	short loc_1

	cmp	ax,8f2h		; VT6103
	jnz	short loc_ex
	cmp	cl,4
	jna	short loc_ex

loc_1:
	push	10h	; PHY configuration 1
	push	[PhyInfo.Phyaddr]
	call	_miiRead
	and	ax,-2
	push	ax
	push	10h
	push	[PhyInfo.Phyaddr]
	call	_miiWrite
	add	sp,(2+3)*2
loc_ex:
	retn
_PhyWorkAround	endp


_hwUpdateMulticast	proc	near
	enter	2+8,0
	push	di
	push	offset semFlt
	call	_EnterCrit

	bt	[MacStatus.sstRxFilter],fltprms
	sbb	ax,ax			; 0/-1
	mov	[bp-10],ax
	mov	[bp-8],ax
	mov	[bp-6],ax
	mov	[bp-4],ax	; clear/set hash table
	jnz	short loc_2	; promiscous mode

	test	[MacStatus.sstRxFilter],mask fltdirect
	jz	short loc_2	; multicast reject

	mov	ax,[MCSTList.curnum]
	dec	ax
	jl	short loc_2	; no multicast
	mov	[bp-2],ax
loc_1:
	mov	ax,[bp-2]
	shl	ax,4		; 16bytes
	add	ax,offset MCSTList.multicastaddr1
	push	ax
	call	_CRC32
	shr	dx,10		; the 6 most significant bits
	pop	ax	; stack adjust
	mov	di,dx
	mov	cx,dx
	shr	di,4
	and	cl,0fh		; the bit index in word
	mov	ax,1
	add	di,di		; the word index (2byte)
	shl	ax,cl
	or	word ptr [bp+di-10],ax
	dec	word ptr [bp-2]
	jge	short loc_1
loc_2:
	mov	eax,dword ptr [bp-10]
	mov	ecx,dword ptr [bp-6]
	mov	gs:[Reg.MAR],eax
	mov	gs:[Reg.MAR][4],ecx

	call	_LeaveCrit
	pop	cx	; stack adjust
	pop	di
	mov	ax,SUCCESS
	leave
	retn
_hwUpdateMulticast	endp

_CRC32		proc	near
POLYNOMIAL_be   equ  04C11DB7h
POLYNOMIAL_le   equ 0EDB88320h

	push	bp
	mov	bp,sp

	push	si
	push	di
	or	ax,-1
	mov	bx,[bp+4]
	mov	ch,3
	cwd

loc_1:
	mov	bp,[bx]
	mov	cl,10h
	inc	bx
loc_2:
IF 1
		; big endian
	ror	bp,1
	mov	si,dx
	xor	si,bp
	shl	ax,1
	rcl	dx,1
	sar	si,15
	mov	di,si
	and	si,highword POLYNOMIAL_be
	and	di,lowword POLYNOMIAL_be
ELSE
		; litte endian
	mov	si,ax
	ror	bp,1
	ror	si,1
	shr	dx,1
	rcr	ax,1
	xor	si,bp
	sar	si,15
	mov	di,si
	and	si,highword POLYNOMIAL_le
	and	di,lowword POLYNOMIAL_le
ENDIF
	xor	dx,si
	xor	ax,di
	dec	cl
	jnz	short loc_2
	inc	bx
	dec	ch
	jnz	short loc_1
	push	dx
	push	ax
	pop	eax
	pop	di
	pop	si
	pop	bp
	retn
_CRC32		endp

_hwUpdatePktFlt	proc	near
	push	offset semFlt
	call	_EnterCrit

	mov	cx,[MacStatus.sstRxFilter]
	mov	al,gs:[Reg.RxCR]
	and	al,not (PA or BA or MA)

	test	cl,mask fltbroad	; broadcast
	jz	short loc_1
	or	al,BA
loc_1:
	test	cl,mask fltprms		; promiscous
	jz	short loc_2
	or	al,PA or BA or MA
loc_2:
	test	cl,mask fltdirect	; pmatch & multicast
	jz	short loc_3
	or	al,MA
	and	gs:[Reg.GCR1],not DAUP	; clear physical match disable
	jmp	short loc_4
loc_3:
	or	gs:[Reg.GCR1],DAUP
loc_4:
	mov	gs:[Reg.RxCR],al

	call	_LeaveCrit
	pop	cx
	call	_hwUpdateMulticast
	mov	ax,SUCCESS
	retn
_hwUpdatePktFlt	endp

_hwSetMACaddr	proc	near
	push	offset semFlt
	call	_EnterCrit

	mov	bx,offset MacChar.mctcsa
	mov	ax,[bx]
	or	ax,[bx+2]
	or	ax,[bx+4]
	jnz	short loc_1	; current address may be valid.
	mov	ax,word ptr [MacChar.mctpsa]	; permanent address
	mov	cx,word ptr [MacChar.mctpsa][2]
	mov	dx,word ptr [MacChar.mctpsa][4]
	mov	[bx],ax		; copy into current address
	mov	[bx+2],cx
	mov	[bx+4],dx
loc_1:
	mov	eax,[bx]
	mov	cx,[bx+4]
	mov	dword ptr gs:[Reg.PAR],eax
	mov	word ptr gs:[Reg.PAR][4],cx

	call	_LeaveCrit
	pop	cx
	mov	ax,SUCCESS
	retn
_hwSetMACaddr	endp

_hwUpdateStat	proc	near
	retn		; do nothing
_hwUpdateStat	endp

_hwClearStat	proc	near
	retn		; do nothing
_hwClearStat	endp

_hwClose	proc	near
	mov	[regIntMask],0
	mov	gs:[Reg.IMR],0
	mov	gs:[Reg.ISR],-1

	mov	al,START
	mov	[regGCR0],al
	mov	gs:[Reg.GCR0],al	; clear TxON / RxON

	mov	al,STOP
	mov	[regGCR0],al
	mov	gs:[Reg.GCR0],al	; set STOP, clear START

	call	_ClearTx

	mov	ax,SUCCESS
	retn
_hwClose	endp

_hwReset	proc	near	; call in bind process
	enter	6,0

	call	_enableMMIO		; memory mapped I/O enable

	xor	ax,ax
	mov	gs:[Reg.IMR],ax
	mov	gs:[Reg.MIMR],al	; disable interrupt
	dec	ax
	mov	gs:[Reg.ISR],ax
	mov	gs:[Reg.MISR],al

	mov	gs:[Reg.GCR1],RESET	; software reset

	mov	word ptr [bp-2],32
loc_1:
	push	96
	call	_Delay1ms
	pop	ax
	test	gs:[Reg.GCR1],RESET	; reset complete?
	jz	short loc_2
	dec	word ptr [bp-2]
	jnz	short loc_1
loc_err:
	mov	ax,HARDWARE_FAILURE
	leave
	retn

loc_2:
	or	gs:[Reg.CFG_A],EELOAD	; eeprom access enable
IF 0
	push	0
	call	_eepRead
	mov	[bp-6],ax
	push	1
	call	_eepRead
	mov	[bp-4],ax
	push	2
	call	_eepRead
	mov	[bp-2],ax
;	add	sp,3*2
ENDIF
	mov	gs:[Reg.EECSR],RELOAD	; reload eeprom contents
IF 0
	mov	ax,[bp-6]		; set station addresses
	mov	cx,[bp-4]
	mov	dx,[bp-2]
	mov	word ptr MacChar.mctpsa,ax	; parmanent
	mov	word ptr MacChar.mctpsa[2],cx
	mov	word ptr MacChar.mctpsa[4],dx
;	mov	word ptr MacChar.mctcsa,ax	; current
;	mov	word ptr MacChar.mctcsa[2],cx
;	mov	word ptr MacChar.mctcsa[4],dx
	mov	word ptr MacChar.mctVendorCode,ax ; vendor
	mov	byte ptr MacChar.mctVendorCode[2],cl
ENDIF
	mov	word ptr [bp-2],32
loc_3:
	push	96
	call	_Delay1ms
	pop	ax
IF 0		; eeprom reload may result in disable MMIO.
	test	gs:[Reg.EECSR],RELOAD	; reload complete?
ELSE
	mov	dx,[IOaddr]
	add	dx,offset Reg.EECSR
	in	al,dx
	test	al,RELOAD
ENDIF
	jz	short loc_4
	dec	word ptr [bp-2]
	jnz	short loc_3
	jmp	short loc_err

loc_4:
	call	_enableMMIO		; enable memory mapped I/O again

	and	gs:[Reg.CFG_A],not EELOAD	; disable eeprom access

	mov	gs:[Reg.WOLCR_CLR],-1	; kill WOL
	mov	gs:[Reg.WOLSR_CLR],-1

	mov	al,[cfgCFGB]		; pci bus
	mov	gs:[Reg.CFG_B],al

	mov	al,gs:[Reg.BCR0]
	and	al,not DMALen
	or	al,[cfgBCR0]		; max DMA length
	mov	gs:[Reg.BCR0],al

	mov	al,gs:[Reg.BCR1]
	and	al,not PollTmr		; desc. polling interval
	or	al,[cfgBCR1]
	mov	gs:[Reg.BCR1],al

	mov	al,gs:[Reg.MII_CFG]
	and	ax,MIIAddr
	mov	[PhyInfo.Phyaddr],ax
	mov	gs:[Reg.MII_CFG],al	; PHY access timing

	mov	al,gs:[Reg.GCR1]
	and	al,not(DAPOLL or RxEarly)
	cmp	[cfgDAPOLL],0
	jz	short loc_5
	or	al,DAPOLL
loc_5:
	mov	gs:[Reg.GCR1],al

	mov	al,gs:[Reg.RxCR]
	and	al,not RxThr
	or	al,[cfgRxDRTH]		; rx drain threshold
	mov	gs:[Reg.RxCR],al

	mov	al,gs:[Reg.TxCR]
	and	al,not (TxThr or LB)
	or	al,[cfgTxDRTH]		; tx drain threshold
	mov	gs:[Reg.TxCR],al

	mov	gs:[Reg.PauseTimer],-1	; XOFF length = -1

	mov	ax,word ptr gs:[Reg.PAR]
	mov	cx,word ptr gs:[Reg.PAR][2]
	mov	dx,word ptr gs:[Reg.PAR][4]
	mov	word ptr MacChar.mctpsa,ax	; parmanent
	mov	word ptr MacChar.mctpsa[2],cx
	mov	word ptr MacChar.mctpsa[4],dx
	mov	word ptr MacChar.mctVendorCode,ax ; vendor
	mov	byte ptr MacChar.mctVendorCode[2],cl

	call	_hwSetMACaddr		; update PAR, set current address
	call	_ResetPhy
loc_ex:
	leave
	retn
_hwReset	endp

_enableMMIO	proc	near
	mov	dx,[IOaddr]
	add	dx,offset Reg.CFG_D
	in	al,dx
	test	al,MMIOE
	jnz	short loc_1
	or	al,MMIOE
	out	dx,al
	in	al,dx		; dummy read
loc_1:
	retn
_enableMMIO	endp


; USHORT miiRead( UCHAR phyaddr, UCHAR phyreg)
_miiRead	proc	near
	push	bp
	mov	bp,sp
	push	offset semMii
	call	_EnterCrit

	mov	gs:[Reg.MII_CR],0
	mov	cx,40h
	push	8
loc_1:
	test	gs:[Reg.MII_PA],MIDLE
	jnz	short loc_2
	call	__IODelayCnt
	dec	cx
	jnz	short loc_1

loc_2:
	mov	al,[bp+6]
	mov	gs:[Reg.MII_PA],al	; reg addr
	mov	gs:[Reg.MII_CR],PHY_RD	; embedded read

	mov	cx,40h
loc_3:
	call	__IODelayCnt
	test	gs:[Reg.MII_CR],PHY_RD
	jz	short loc_4
	dec	cx
	jnz	short loc_3
loc_4:
	mov	ax,gs:[Reg.MII_RWDR]
	pop	cx	; stack adjust
	call	_LeaveCrit
	leave
	retn
_miiRead	endp

; VOID miiWrite( UCHAR phyaddr, UCHAR phyreg, USHORT value)
_miiWrite	proc	near
	push	bp
	mov	bp,sp
	push	offset semMii
	call	_EnterCrit

	mov	gs:[Reg.MII_CR], 0	; clear MAUTO, MDPM
					; embedded mode  phyaddr ignored
	mov	cx,40h
	push	8
loc_1:
	test	gs:[Reg.MII_PA],MIDLE	; polling cycle active?
	jnz	short loc_2
	call	__IODelayCnt
	dec	cx
	jnz	short loc_1
loc_2:
	mov	cl,[bp+6]		; register
	mov	ax,[bp+8]		; data value

	mov	gs:[Reg.MII_PA],cl
	mov	gs:[Reg.MII_RWDR],ax
	mov	gs:[Reg.MII_CR],PHY_WR

	mov	cx,40h
loc_3:
	call	__IODelayCnt
	test	gs:[Reg.MII_CR],PHY_WR
	jz	short loc_4
	dec	cx
	jnz	short loc_3
loc_4:
	pop	cx	; stack adjust
	call	_LeaveCrit
	leave
	retn
_miiWrite	endp

; VOID miiReset( VOID )
_miiReset	proc	near
	push	offset semMii
	call	_EnterCrit
	mov	bx,offset Reg.MII_CR
	push	2

	mov	gs:[bx],byte ptr 0	; clear auto-polling
	mov	cx,100h
loc_1:
	test	gs:[Reg.MII_PA],MIDLE
	jnz	short loc_2
	call	__IODelayCnt
	dec	cx
	jnz	short loc_1
loc_2:
	mov	cx,32			; 32clocks
loc_3:
	mov	al,MOUT or MDIOE or MDPM	; high
	mov	byte ptr gs:[bx],al
	call	__IODelayCnt
	or	al,MCLK
	mov	gs:[bx],al
	call	__IODelayCnt
	loop	short loc_3

	pop	cx	; stack adjust
	call	_LeaveCrit
	pop	cx	; stack adjust
loc_ex:
	retn
_miiReset	endp


IF 0
; USHORT eepRead( UCHAR addr )
_eepRead	proc	near
	push	bp
	mov	bp,sp
	mov	bx,offset Reg.EECSR


	mov	al,EDPM
	mov	gs:[bx],al	; chip select - low
;	push	1
	push	4
	call	__IODelayCnt
	or	al,ECLK
	mov	gs:[bx],al
	call	__IODelayCnt

	mov	dl,[bp+4]		; address
	mov	dh,0
	mov	cx,(1 + 2 + 6) -1	; length
	or	dx,110b shl 6		; start + read

loc_1:
	xor	ax,ax
	bt	dx,cx
	rcl	ax,2
	or	al,EDPM or ECS
	mov	gs:[bx],al
	call	__IODelayCnt
	or	al,ECLK
	mov	gs:[bx],al
	call	__IODelayCnt
	dec	cx
	jge	short loc_1

	mov	cx,16
	xor	dx,dx
loc_2:
	mov	al,EDPM or ECS
	mov	gs:[bx],al
	call	__IODelayCnt
	or	al,ECLK
	mov	gs:[bx],al
	call	__IODelayCnt
	mov	al,gs:[bx]
	shr	ax,1
	rcl	dx,1
	dec	cx
	jnz	short loc_2

	mov	al,EDPM		; chip select low
	mov	gs:[bx],al
	call	__IODelayCnt
	or	al,ECLK
	mov	gs:[bx],al
	call	__IODelayCnt

	pop	cx	; stack adjust
	pop	bp
	mov	ax,dx
	retn
_eepRead	endp
ENDIF

; void _IODelayCnt( USHORT count )
__IODelayCnt	proc	near
	push	bp
	mov	bp,sp
	push	cx
	mov	bp,[bp+4]
loc_1:
	mov	cx,offset DosIODelayCnt
	dec	bp
	loop	$
	jnz	short loc_1
	pop	cx
	pop	bp
	retn
__IODelayCnt	endp


_TEXT	ends
end
