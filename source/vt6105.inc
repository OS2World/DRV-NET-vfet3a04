; *** VIA VT6105 Rhine III definition ***

; +++ register definition +++
Rhine3_registers	struc
PAR		db	6 dup(?) ; 00 physical address
RxCR		db	?	; 06 receive control
TxCR		db	?	; 07 transmit control
GCR0		db	?	; 08 command 0 (global)
GCR1		db	?	; 09 command 1
		dw	?	; 0a
ISR		dw	?	; 0c interrupt status
IMR		dw	?	; 0e interrupt mask
MAR		dd	?,?	; 10 multicast hash table
RxDBA		dd	?	; 18 receive descriptor base
TxDBA		dd	?	; 1c transmit descriptor base
		db	1ch dup(?) ; 20-3b
		db	30h dup(?) ; 3c-6b
MII_CFG		db	?	; 6c mii configuration
MII_SR		db	?	; 6d mii status
BCR0		db	?	; 6e bus control 0
BCR1		db	?	; 6f bus control 1
MII_CR		db	?	; 70 mii control
MII_PA		db	?	; 71 mii port address
MII_RWDR	dw	?	; 72 mii R/W data port
EECSR		db	?	; 74 eeprom control/status
		db	3 dup(?) ; 75-77
CFG_A		db	?	; 78 chip configuration A
CFG_B		db	?	; 79 chip configuration B
CFG_C		db	?	; 7a chip configuration C
CFG_D		db	?	; 7b chip configuration D
		dd	?	; 7c
MCR0		db	?	; 80 misc command 0
MCR1		db	?	; 81 misc command 1
PMCCR		db	?	; 82 PM capability control
STICKHW		db	?	; 83 sticky bit H/W shadow
MISR		db	?	; 84 misc interrupt status
		db	?	; 85
MIMR		db	?	; 86 misc interrupt mask
		db	?	; 87
		dd	?	; 88
		db	6 dup(?) ; 8c-91 flush
		db	6 dup(?) ; 92-97
FCR0		db	?	; 98 flow control 0
FCR1		db	?	; 99 flow control 1
PauseTimer	dw	?	; 9a pause timer
		dd	?	; 9c
WOLCR_SET	db	?	; a0 WOL command set
PWCFG_SET	db	?	; a1 power configuration set
		db	?	; a2
WOLCG_SET	db	?	; a3 WOL control set
WOLCR_CLR	db	?	; a4 WOL command clear
PWCFG_CLR	db	?	; a5 power configuration clear
		db	?	; a6
WOLCG_CLR	db	?	; a7 WOL control clear
WOLSR_SET	db	?	; a8 WOL status set?
		db	3 dup(?) ; a9-ab
WOLSR_CLR	db	?	; ac WOL status clear
		db	3 dup(?) ; ad-af
CRC0		dd	?	; b0 CRC pattern 0
CRC1		dd	?	; b4
CRC2		dd	?	; b8
CRC3		dd	?	; bc
ByteMask0	dd	4 dup(?) ; c0 byte mask 0
ByteMask1	dd	4 dup(?) ; d0
ByteMask2	dd	4 dup(?) ; e0
ByteMask3	dd	4 dup(?) ; f0
Rhine3_registers	ends

; --- Receive configuration 06h ---
RxThr		equ	0e0h	; receive FIFO threshold (mask)
PA		equ	 10h	; all unicast accept
BA		equ	  8	; broadcast accept
MA		equ	  4	; multicast hash hit accept
RUNT		equ	  2	; runt packet accept
SEP		equ	  1	; CRC errored packet accept

RxThr_64	equ	(000b shl 5)
RxThr_32	equ	(001b shl 5)
RxThr_128	equ	(010b shl 5)
RxThr_256	equ	(011b shl 5)
RxThr_512	equ	(100b shl 5)
RxThr_768	equ	(101b shl 5)
RxThr_1024	equ	(110b shl 5)
RxThr_SF	equ	(111b shl 5)


; --- Transmit configuration 07h ---
TxThr		equ	0e0h	; transmit FIFO threshold (mask)
OFSET		equ	  8	: back-off priority select
LB		equ	  6	; loopback mode (mask)

TxThr_128	equ	(000b shl 5)
TxThr_256	equ	(001b shl 5)
TxThr_512	equ	(010b shl 5)
TxThr_1024	equ	(011b shl 5)
TxThr_SF	equ	(100b shl 5)


; --- control 0  08h ---
RxDMD		equ	40h	; receive poll demand (self clear)
TxDMD		equ	20h	; transmit poll demand (self clear)
TxON		equ	10h	; transmit enable
RxON		equ	 8	; receive enable
STOP		equ	 4	; stop NIC
START		equ	 2	; start NIC

; --- control 1  09h ---
RESET		equ	80h	; software reset (self clear)
DAPOLL		equ	 8	; disable TD/RD auto polling
FDX		equ	 4	; full duplex mode
DAUP		equ	 2	; reject physical match packet
RxEarly		equ	 1	; enable early recieve mode

; --- interrupt status/mask  0ch/0eh ---
GPI		equ	8000h	; general purpose interrupt
PSC		equ	4000h	; port state change
TxABT		equ	2000h	; excessive collision tx abort
RDU		equ	1000h	; RD running up
RQOVF		equ	 800h	; receive FIFO queue list overflow
ROVF		equ	 400h	; receive FIFO overflow
TURN		equ	 200h	; transmit FIFO underrun
RERL		equ	 100h	; early receive
BE		equ	  40h	; PCI bus error
RBE		equ	  20h	; receive buffer link error
TBE		equ	  10h	; transmit buffer underflow
TXE		equ	   8	; transmit error
RXE		equ	   4	; receive error
PTX		equ	   2	; transmit success
PRX		equ	   1	; receive success

I_RX		equ	PRX or RXE or RBE or ROVF or RQOVF or RDU
I_TX		equ	PTX or TXE or TBE or TURN or TxABT

; --- MII configuration  6ch ---
MIIPollTmr	equ	0e0h	; MII management polling timer interval(mask)
MIISpeed	equ	 20h	; accelate management data clock speed
MIIAddr		equ	 1fh	; PHY device address

; --- MII status  6dh ---
SPHYRST		equ	80h	; software PHY reset
NWASYM		equ	40h	; asymmetric pause status
NWSYM		equ	20h	; symmetric pause status
NWLINKF		equ	10h	; link fail status
PHYERR		equ	 8	; PHY received error
NWDPX		equ	 4	; duplex mode
LINKF		equ	 2	; link fail status
MDSPD		equ	 1	; medium speed  0:100, 1:10

; --- bus control 0  6eh ---
DMALen		equ	7	; DMA length (mask)

DMALen_32	equ	000b
DMALen_64	equ	001b
DMALen_128	equ	010b
DMALen_256	equ	011b
DMALen_512	equ	100b
DMALen_1024	equ	101b
DMALen_SF	equ	110b


; --- bus control 1  6fh ---
PollTmr		equ	7	; Polling Time Interval (mask)

; --- MII control  70h ---
MAUTO		equ	80h	; MII management port auto polling enable
PHY_RD		equ	40h	; PHY read enable (self clear)
PHY_WR		equ	20h	; PHY write enable (self clear)
MDPM		equ	10h	; direct programming mode
MDIOE		equ	 8	; MDIO output enable indicator
MOUT		equ	 4	; data out
MIN		equ	 2	; data in
MCLK		equ	 1	; clock

; --- management interface address  71h ---
MIDLE		equ	80h	; MII idle (read only)
MSRCEN		equ	40h	; MII status change enable
MDONE		equ	20h	; pause status/control
MAD		equ	1fh	; MII port address (mask)

; --- EEPROM control/status 74h ---
EEPR		equ	80h	; EEPROM programmed status(read only)
RELOAD		equ	20h	; dynamic reload EEPROM content
EDPM		equ	10h	; direct program mode
ECS		equ	 8	; chip select
ECLK		equ	 4	; clock
EIN		equ	 2	; data in
EOUT		equ	 1	; data out (read only)

; --- chip configuration A  78h ---
EELOAD		equ	80h	; EEPROM embedded and direct programming
MIIOPT		equ	40h	; MII option
LEDSEL		equ	0eh	; LED select (mask)

; --- chip configuration B  79h ---
TxFQD		equ	80h	; transmit frame queuing disable
DPGD		equ	40h	; data parity generation and checking disable
MRLDIS		equ	20h	; memory read line disable
TxARB		equ	10h	; Tx DMA interleave to Rx DMA
RxARB		equ	 8	; Rx DMA interleave to Tx DMA
MRWAIT		equ	 4	; read insert one wait
MWWAIT		equ	 2	; write insert one wait
LATMEN		equ	 1	; latency timer

; --- chip configuration D 7bh ---
MMIOE		equ	80h	; memory mapped IO access enable
DIAG		equ	40h	; diagnostic mode
RNDBF		equ	 8	; random backoff algorithm
CAPEF		equ	 6	; capture effect solution select(mask)
BFOPT		equ	 1	; backoff algorithm optional

; --- misc control 0  80h ---
MFTXFEN		equ	10h	; transmit full-duplex flow control
MFRXFEN		equ	 8	; receive full-duplex flow control
MHFEN		equ	 4	; half-duplex flow control(back pressure)
Tmr0Spd		equ	 2	; timer 0 suspend
Tmr0EN		equ	 1	; timer 0 count enable

; --- misc control 1  81h ---
SRST		equ	80h	; software generated suspend reset
PMVer		equ	10h	; power management unit support version
TmrRes		equ	 4	; soft timer resolution in micro seconds
PHYINT		equ	 2	; PHY event interrupt
Tmr1EN		equ	 1	; software timer 1 count enable

; --- sticky hardware  83h ---
LegacyWOLStat	equ	8	; legacy WOL status
LegacyWOLEn	equ	4	; legacy WOL enable
Sticky_DS1	equ	2	; 
Sticky_DS0	equ	1	; 

; --- MII interrupt status/mask  84h/86h ---
Tmr1I		equ	2
Tmr0I		equ	1

; --- flow control 1  99h ---
XLTH		equ	0e0h	; tx pause low(XOFF) threshold (mask)
XHITH		equ	 30h	; tx pause high(XON) threshold (mask)
XONEN		equ	  8	; XON/XOFF mode
FDXTFCEN	equ	  4	; full duplex flow control on tx side
FDXRFCEN	equ	  2	; full duplex flow control on rx side
HDXFCEN		equ	  1	; half duplex flow control

XLTH_4		equ	(00b shl 6)
XLTH_8		equ	(01b shl 6)
XLTH_16		equ	(10b shl 6)
XLTH_24		equ	(11b shl 6)

XHITH_24	equ	(00b shl 4)
XHITH_32	equ	(01b shl 4)
XHITH_48	equ	(10b shl 4)
XHITH_64	equ	(11b shl 4)


; --- WOL set/clear  (a0h/a4h)/(a8h/ach) ---
WOL_LINKOFF	equ	80h	; link off
WOL_LINKON	equ	40h	; link on
WOL_Magic	equ	20h	; magic packet
WOL_UNI		equ	10h	; unicast
WOL_PAT3	equ	 8	; pattern 3
WOL_PAT2	equ	 4	; pattern 2
WOL_PAT1	equ	 2	; pattern 1
WOL_PAT0	equ	 1	; pattern 0

; --- Power configuration set/clear  a1h/a5h ---
PHY_PWD		equ	80h	; PHY power down option
ISLC		equ	40h	; internal sticky logic control
WOLPSC		equ	20h	; WOL pin signaling control
LWOL		equ	10h	; legacy WOL
PME_SR		equ	 8	; pci config PME_STS shadow
PME_EN		equ	 4	; pci config PME_EN shadow
WOL_SR		equ	 2	; legacy WOL_SR shadow
WOL_EN		equ	 1	; legacy WOL_EN shadow

; --- WOL configuration set/clear  a3h/a7h ---
PME_OVR		equ	80h	; power management over
WOL_FDX		equ	40h	; 
WOL_MA		equ	20h	; 
WOL_BA		equ	10h	; 


; +++ transmit / receive descriptor definition +++
; --- transmit descriptor ---
TD	struc
sts	dd	?	; status
ctl	dd	?	; control
buf	dd	?	; buffer address
lnk	dd	?	; next link address
	; --- above for hardware, below for driver
phys	dd	?	; physical address of this descriptor
cnt	dw	?	; number of fragments
vlnk	dw	?	; logical link
TD	ends

; --- receive descriptor ---
RD	struc
sts	dd	?	; status
ctl	dd	?	; control
buf	dd	?	; buffer address
lnk	dd	?	; next link address
	; --- above for hardware, below for driver
vbuf	dd	?	; virtual addresse of buf
phys	dd	?	; physical addresse of this descriptor
tail	dw	?	; tail fragment of the frame
cnt	dw	?	; reserved (number of fragments)
blnk	dw	?	; logical link of protocol
vlnk	dw	?	; logical link
RD	ends

; --- virtual transmit descriptor (for driver) ---
vtxd		struc
head		dw	?	; frame head fragment
tail		dw	?	; frame tail fragment
reqhandle	dw	?	; request handle
protid		dw	?	; protocol id
cnt		dw	?	; number of fragments
vlnk		dw	?	; logical link
immedphys	dd	?	; physical addresse of immediate data buffer
immed		db	64 dup(?) ; reserved buffer for immediate data
vtxd		ends

; --- transmit status bits ---
OWN		equ	80000000h	; owner
TERR		equ	    8000h	; transmit error
UDF		equ	     800h	; FIFO underflow
CRS		equ	     400h	; carrier sense lost detect
OWC		equ	     200h	; out of window collision
ABT		equ	     100h	; excessive collision
CDH		equ	      80h	; CD heart beat check failure
COLS		equ	      10h	; collision detect
NCR		equ	      0fh	; # of collision retries (mask)

; --- transmit control bits ---
IC		equ	800000h	; interrupt control
; --- !? reverse in datasheet definition !? ---
;TxSTP		equ	400000h	; packet start  11:single 10:more
;TxEDP		equ	200000h	; packet end    01:end  00:invalid
TxEDP		equ	400000h	; packet end    10:end  00:invalid
TxSTP		equ	200000h	; packet start  11:single 01:more
CRC		equ	 10000h	; disable CRC generation
TxCHN		equ	  8000h	; chain structure  1:chain 0:ring

; --- receive status bits ---
;OWN		equ	80000000h
RxLen		equ	7fff0000h	; receive length
RXOK		equ	    8000h	; no receive errors
MAR		equ	    2000h	; multicast
BAR		equ	    1000h	; broadcast
PHY		equ	     800h	; physical match
RxCHN		equ	     400h	; chain, always 1
RxSTP		equ	     200h	; packet start  11:single
RxEDP		equ	     100h	; paclet end  10:more  01:end
BUFE		equ	      80h	; link structure error
RxRUNT		equ	      20h	; runt
LONG		equ	      10h	; length > 1518bytes
FOV		equ	       8	; FIFO Overflow
FAE		equ	       4	; frame align error
CRCE		equ	       2	; CRC error
RERR		equ	       1	; receive errors


