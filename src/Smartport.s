;*******************************
;
; Apple][Sd Firmware
; Version 1.2
; Smartport functions
;
; (c) Florian Reitz, 2017 - 2018
;
; X register usually contains SLOT16
; Y register is used for counting or SLOT
;
;*******************************
            
.export SMARTPORT

.import READ
.import WRITE

.include "AppleIISd.inc"
.segment "EXTROM"


;*******************************
;
; Smartport command dispatcher
;
; $42-$47 MLI input locations
; X Slot*16
; Y Slot
;
; C Clear - No error
;   Set   - Error
; A $00   - No error
;   $01   - Unknown command
;
;*******************************

SMARTPORT:  LDY   #SMZPSIZE-1   ; save zeropage area for Smarport
@SAVEZP:    LDA   SMZPAREA,Y
            PHA
            DEY
            BPL   @SAVEZP

            TSX                 ; get parameter list pointer
            LDA   $101+SMZPSIZE,X
            STA   SMPARAMLIST
            CLC
            ADC   #3            ; adjust return address
            STA   $101+SMZPSIZE,X
            LDA   $102+SMZPSIZE,X
            STA   SMPARAMLIST+1
            ADC   #0
            STA   $102+SMZPSIZE,X

            LDY   #1            ; get command code
            LDA   (SMPARAMLIST),Y 
            STA   SMCMD
            INY
            LDA   (SMPARAMLIST),Y
            TAX
            INY
            LDA   (SMPARAMLIST),Y
            STA   SMPARAMLIST+1 ; TODO: why overwrite, again?
            STX   SMPARAMLIST

            LDA   #ERR_BADCMD   ; suspect bad command
            LDX   SMCMD
            CPX   #$09+1        ; command too large
            BCS   @END

            LDA   (SMPARAMLIST) ; parameter count
            CMP   REQPARAMCOUNT,X
            BNE   @COUNTMISMATCH

            LDY   #1            ; get drive number
            LDA   (SMPARAMLIST),Y
            LDY   SLOT
            STA   DRVNUM,Y

            TXA
            ASL   A             ; shift for use or word addresses
            TAX
            JSR   @JMPSPCOMMAND ; Y holds SLOT
            BCS   @END          ; jump on error
            LDA   #NO_ERR

@END:       TAX                 ; save retval
            LDY   #0            ; restore zeropage
@RESTZP:    PLA
            STA   SMZPAREA,Y
            INY
            CPY   #SMZPSIZE
            BCC   @RESTZP

            TXA
            LDY   #2            ; highbyte of # bytes transferred
            LDY   #0            ; low byte of # bytes transferred
            CMP   #1            ; C=1 if A != NO_ERR
            RTS

@COUNTMISMATCH:
            LDA   #ERR_BADPCNT
            BRA   @END
            
@JMPSPCOMMAND:                  ; use offset from cmd*2
            JMP   (SPDISPATCH,X)
            


; Required parameter counts for the commands
REQPARAMCOUNT:
            .byt 3              ; 0 = status
            .byt 3              ; 1 = read block
            .byt 3              ; 2 = write block
            .byt 1              ; 3 = format
            .byt 3              ; 4 = control
            .byt 1              ; 5 = init
            .byt 1              ; 6 = open
            .byt 1              ; 7 = close
            .byt 4              ; 8 = read char
            .byt 4              ; 9 = write char

; Command jump table
SPDISPATCH:
            .word SMSTATUS
            .word SMREADBLOCK
            .word SMWRITEBLOCK
            .word SMFORMAT
            .word SMCONTROL
            .word SMINIT
            .word SMOPEN
            .word SMCLOSE
            .word SMREADCHAR
            .word SMWRITECHAR



SMSTATUS:
SMCONTROL:


; Smartport Read Block command
;
; reads a 512-byte block using the ProDOS function
;
SMREADBLOCK:
            JSR   TRANSLATE
            BCC   @READ
            RTS

@READ:      LDX   SLOT16
            LDY   SLOT
            JMP   READ          ; call ProDOS read



; Smartport Write Block command
;
; writes a 512-byte block using the ProDOS function
;
SMWRITEBLOCK:
            JSR   TRANSLATE
            BCC   @WRITE
            RTS

@WRITE:     LDX   SLOT16
            LDY   SLOT
            JMP   WRITE     ; call ProDOS write


; Translates the Smartport unit number to a ProDOS device
; and prepares the block number
;
; Unit 0: entire chain, not supported
; Unit 1: this slot, drive 0
; Unit 2: this slot, drive 1
; unit 3: phantom slot, drive 0
; unit 4: phantom slot, drive 1
;
TRANSLATE:  LDA   DRVNUM,Y
            BEQ   @BADUNIT       ; not supportd for unit 0
            CMP   #1
            BEQ   @UNIT1
            CMP   #2
            BEQ   @UNIT2
            CMP   #3
            BEQ   @UNIT3
            CMP   #4
            BEQ   @UNIT4
            BRA   @BADUNIT      ; only 4 partitions are supported

@UNIT1:     LDA   SLOT16        ; this slot
            BRA   @STORE
@UNIT2:     LDA   SLOT16
            ORA   #$80          ; drive 1
            BRA   @STORE
@UNIT3:     LDA   SLOT16
            DEC   A             ; phantom slot
            BRA   @STORE
@UNIT4:     LDA   SLOT16
            DEC   A             ; phantom slot
            ORA   #$80          ; drive 1

@STORE:     STA   DSNUMBER      ; store in ProDOS variable

            LDY   #2            ; get buffer pointer
            LDA   (SMPARAMLIST),Y
            STA   BUFFER
            INY
            LDA   (SMPARAMLIST),Y
            STA   BUFFER+1

            INY                 ; get block number
            LDA   (SMPARAMLIST),Y
            STA   BLOCKNUM
            INY
            LDA   (SMPARAMLIST),Y
            STA   BLOCKNUM+1
            INY
            LDA   (SMPARAMLIST),Y
            BNE   @BADBLOCK     ; bit 23-16 need to be 0

            CLC
            RTS

@BADUNIT:   LDA   #ERR_BADUNIT
            SEC
            RTS

@BADBLOCK:  LDA   #ERR_BADBLOCK
            SEC
            RTS


; Smartport Format command
;
; supported, but doesn't do anything
;
SMFORMAT:   LDA   #NO_ERR
            CLC
            RTS


; Smartport Init comand
;
; throw error if DRVNUM is not 0, else do nothing
;
SMINIT:     LDA   DRVNUM,Y
            CLC
            BEQ   @END          ; error if not 0
            LDA   #ERR_BADUNIT
            SEC
@END:       RTS


; Smartport Open and Close commands
;
; supported for character devices, only
;
SMOPEN:
SMCLOSE:    LDA   #ERR_BADCMD
            SEC
            RTS


; Smartport Read Character and Write Character
;
; only 512-byte block operations are supported
;
SMREADCHAR:
SMWRITECHAR:
            LDA   #ERR_IOERR
            SEC
            RTS
