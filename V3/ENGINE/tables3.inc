; GENERADO por SCUMM/V3/TOOLS/gen_vmtables3.py: no editar a mano

; ---- tabla de despacho (alineada a 256): manejador de cada opcode, bytes bajo y alto
                defs (256 - ($ & 255)) & 255
disp_lo:
        defb h3_stopObjectCode & 255   ; 00 stopObjectCode
        defb h3_ovb & 255   ; 01 putActor
        defb h3_ovb & 255   ; 02 startMusic
        defb h3_ovb & 255   ; 03 getActorRoom
        defb h3_isGreaterEqual & 255   ; 04 isGreaterEqual
        defb h_host & 255   ; 05 drawObject
        defb h3_ovb & 255   ; 06 getActorElevation
        defb h3_ovb & 255   ; 07 setState
        defb h3_isNotEqual & 255   ; 08 isNotEqual
        defb h3_ovb & 255   ; 09 faceActor
        defb h3_startScript & 255   ; 0A startScript
        defb h_host_r & 255   ; 0B getVerbEntrypoint
        defb h3_ovb & 255   ; 0C resourceRoutines
        defb h_host & 255   ; 0D walkActorToActor
        defb h3_ovb & 255   ; 0E putActorAtObject
        defb h3_ovb & 255   ; 0F ifState
        defb h3_ovb & 255   ; 10 getObjectOwner
        defb h3_ovb & 255   ; 11 animateActor
        defb h3_ovb & 255   ; 12 panCameraTo
        defb h3_ovb & 255   ; 13 actorOps
        defb h3_ovb & 255   ; 14 print
        defb h3_ovb & 255   ; 15 actorFromPos
        defb h3_getRandomNr & 255   ; 16 getRandomNr
        defb h3_and & 255   ; 17 and
        defb h3_jumpRelative & 255   ; 18 jumpRelative
        defb h_host & 255   ; 19 doSentence
        defb h3_move & 255   ; 1A move
        defb h3_multiply & 255   ; 1B multiply
        defb h3_ovb & 255   ; 1C startSound
        defb h3_ovb & 255   ; 1D ifClassOfIs
        defb h_host & 255   ; 1E walkActorTo
        defb h_host_j & 255   ; 1F isActorInBox
        defb h3_ovb & 255   ; 20 stopMusic
        defb h3_ovb & 255   ; 21 putActor
        defb h3_ovb & 255   ; 22 saveLoadGame
        defb h3_ovb & 255   ; 23 getActorY
        defb h_host & 255   ; 24 loadRoomWithEgo
        defb h_host & 255   ; 25 pickupObject
        defb h3_setVarRange & 255   ; 26 setVarRange
        defb h3_ovb & 255   ; 27 stringOps
        defb h3_equalZero & 255   ; 28 equalZero
        defb h3_ovb & 255   ; 29 setOwnerOf
        defb h3_startScript & 255   ; 2A startScript
        defb h3_delayVariable & 255   ; 2B delayVariable
        defb h3_ovb & 255   ; 2C cursorCommand
        defb h3_ovb & 255   ; 2D putActorInRoom
        defb h3_delay & 255   ; 2E delay
        defb h3_ovb & 255   ; 2F ifNotState
        defb h_host & 255   ; 30 setBoxFlags
        defb h3_ovb & 255   ; 31 getInventoryCount
        defb h3_ovb & 255   ; 32 setCameraAt
        defb h3_ovb & 255   ; 33 roomOps
        defb h3_ovb & 255   ; 34 getDist
        defb h_host_r & 255   ; 35 findObject
        defb h_host & 255   ; 36 walkActorToObject
        defb h_host & 255   ; 37 startObject
        defb h3_isLessEqual & 255   ; 38 isLessEqual
        defb h_host & 255   ; 39 doSentence
        defb h3_subtract & 255   ; 3A subtract
        defb h_host & 255   ; 3B waitForActor
        defb h3_ovb & 255   ; 3C stopSound
        defb h3_ovb & 255   ; 3D findInventory
        defb h_host & 255   ; 3E walkActorTo
        defb h_host & 255   ; 3F drawBox
        defb h3_cutscene & 255   ; 40 cutscene
        defb h3_ovb & 255   ; 41 putActor
        defb h3_chainScript & 255   ; 42 chainScript
        defb h3_ovb & 255   ; 43 getActorX
        defb h3_isLess & 255   ; 44 isLess
        defb h_host & 255   ; 45 drawObject
        defb h3_increment & 255   ; 46 increment
        defb h3_ovb & 255   ; 47 setState
        defb h3_isEqual & 255   ; 48 isEqual
        defb h3_ovb & 255   ; 49 faceActor
        defb h3_startScript & 255   ; 4A startScript
        defb h_host_r & 255   ; 4B getVerbEntrypoint
        defb h_host & 255   ; 4C waitForSentence
        defb h_host & 255   ; 4D walkActorToActor
        defb h3_ovb & 255   ; 4E putActorAtObject
        defb h3_ovb & 255   ; 4F ifState
        defb h_host & 255   ; 50 pickupObject
        defb h3_ovb & 255   ; 51 animateActor
        defb h3_ovb & 255   ; 52 actorFollowCamera
        defb h3_ovb & 255   ; 53 actorOps
        defb h3_ovb & 255   ; 54 setObjectName
        defb h3_ovb & 255   ; 55 actorFromPos
        defb h3_ovb & 255   ; 56 getActorMoving
        defb h3_or & 255   ; 57 or
        defb h3_beginOverride & 255   ; 58 beginOverride
        defb h_host & 255   ; 59 doSentence
        defb h3_add & 255   ; 5A add
        defb h3_divide & 255   ; 5B divide
        defb h_host & 255   ; 5C oldRoomEffect
        defb h3_ovb & 255   ; 5D setClass
        defb h_host & 255   ; 5E walkActorTo
        defb h_host_j & 255   ; 5F isActorInBox
        defb h3_freezeScripts & 255   ; 60 freezeScripts
        defb h3_ovb & 255   ; 61 putActor
        defb h3_stopScript & 255   ; 62 stopScript
        defb h3_ovb & 255   ; 63 getActorFacing
        defb h_host & 255   ; 64 loadRoomWithEgo
        defb h_host & 255   ; 65 pickupObject
        defb h3_ovb & 255   ; 66 getClosestObjActor
        defb h3_ovb & 255   ; 67 getStringWidth
        defb h3_isScriptRunning & 255   ; 68 isScriptRunning
        defb h3_ovb & 255   ; 69 setOwnerOf
        defb h3_startScript & 255   ; 6A startScript
        defb h3_debug & 255   ; 6B debug
        defb h3_ovb & 255   ; 6C getActorWidth
        defb h3_ovb & 255   ; 6D putActorInRoom
        defb h3_stopObjectScript & 255   ; 6E stopObjectScript
        defb h3_ovb & 255   ; 6F ifNotState
        defb h3_ovb & 255   ; 70 lights
        defb h3_ovb & 255   ; 71 getActorCostume
        defb h_host & 255   ; 72 loadRoom
        defb h3_ovb & 255   ; 73 roomOps
        defb h3_ovb & 255   ; 74 getDist
        defb h_host_r & 255   ; 75 findObject
        defb h_host & 255   ; 76 walkActorToObject
        defb h_host & 255   ; 77 startObject
        defb h3_isGreater & 255   ; 78 isGreater
        defb h_host & 255   ; 79 doSentence
        defb h3_ovb & 255   ; 7A verbOps
        defb h3_ovb & 255   ; 7B getActorWalkBox
        defb h3_ovb & 255   ; 7C isSoundRunning
        defb h3_ovb & 255   ; 7D findInventory
        defb h_host & 255   ; 7E walkActorTo
        defb h_host & 255   ; 7F drawBox
        defb h3_breakHere & 255   ; 80 breakHere
        defb h3_ovb & 255   ; 81 putActor
        defb h3_ovb & 255   ; 82 startMusic
        defb h3_ovb & 255   ; 83 getActorRoom
        defb h3_isGreaterEqual & 255   ; 84 isGreaterEqual
        defb h_host & 255   ; 85 drawObject
        defb h3_ovb & 255   ; 86 getActorElevation
        defb h3_ovb & 255   ; 87 setState
        defb h3_isNotEqual & 255   ; 88 isNotEqual
        defb h3_ovb & 255   ; 89 faceActor
        defb h3_startScript & 255   ; 8A startScript
        defb h_host_r & 255   ; 8B getVerbEntrypoint
        defb h3_ovb & 255   ; 8C resourceRoutines
        defb h_host & 255   ; 8D walkActorToActor
        defb h3_ovb & 255   ; 8E putActorAtObject
        defb h3_ovb & 255   ; 8F ifState
        defb h3_ovb & 255   ; 90 getObjectOwner
        defb h3_ovb & 255   ; 91 animateActor
        defb h3_ovb & 255   ; 92 panCameraTo
        defb h3_ovb & 255   ; 93 actorOps
        defb h3_ovb & 255   ; 94 print
        defb h3_ovb & 255   ; 95 actorFromPos
        defb h3_getRandomNr & 255   ; 96 getRandomNr
        defb h3_and & 255   ; 97 and
        defb h3_ovb & 255   ; 98 systemOps
        defb h_host & 255   ; 99 doSentence
        defb h3_move & 255   ; 9A move
        defb h3_multiply & 255   ; 9B multiply
        defb h3_ovb & 255   ; 9C startSound
        defb h3_ovb & 255   ; 9D ifClassOfIs
        defb h_host & 255   ; 9E walkActorTo
        defb h_host_j & 255   ; 9F isActorInBox
        defb h3_stopObjectCode & 255   ; A0 stopObjectCode
        defb h3_ovb & 255   ; A1 putActor
        defb h3_ovb & 255   ; A2 saveLoadGame
        defb h3_ovb & 255   ; A3 getActorY
        defb h_host & 255   ; A4 loadRoomWithEgo
        defb h_host & 255   ; A5 pickupObject
        defb h3_setVarRange & 255   ; A6 setVarRange
        defb h3_ovb & 255   ; A7 saveLoadVars
        defb h3_notEqualZero & 255   ; A8 notEqualZero
        defb h3_ovb & 255   ; A9 setOwnerOf
        defb h3_startScript & 255   ; AA startScript
        defb h3_ovb & 255   ; AB saveRestoreVerbs
        defb h3_expression & 255   ; AC expression
        defb h3_ovb & 255   ; AD putActorInRoom
        defb h3_wait & 255   ; AE wait
        defb h3_ovb & 255   ; AF ifNotState
        defb h_host & 255   ; B0 setBoxFlags
        defb h3_ovb & 255   ; B1 getInventoryCount
        defb h3_ovb & 255   ; B2 setCameraAt
        defb h3_ovb & 255   ; B3 roomOps
        defb h3_ovb & 255   ; B4 getDist
        defb h_host_r & 255   ; B5 findObject
        defb h_host & 255   ; B6 walkActorToObject
        defb h_host & 255   ; B7 startObject
        defb h3_isLessEqual & 255   ; B8 isLessEqual
        defb h_host & 255   ; B9 doSentence
        defb h3_subtract & 255   ; BA subtract
        defb h_host & 255   ; BB waitForActor
        defb h3_ovb & 255   ; BC stopSound
        defb h3_ovb & 255   ; BD findInventory
        defb h_host & 255   ; BE walkActorTo
        defb h_host & 255   ; BF drawBox
        defb h3_endCutscene & 255   ; C0 endCutscene
        defb h3_ovb & 255   ; C1 putActor
        defb h3_chainScript & 255   ; C2 chainScript
        defb h3_ovb & 255   ; C3 getActorX
        defb h3_isLess & 255   ; C4 isLess
        defb h_host & 255   ; C5 drawObject
        defb h3_decrement & 255   ; C6 decrement
        defb h3_ovb & 255   ; C7 setState
        defb h3_isEqual & 255   ; C8 isEqual
        defb h3_ovb & 255   ; C9 faceActor
        defb h3_startScript & 255   ; CA startScript
        defb h_host_r & 255   ; CB getVerbEntrypoint
        defb h_host & 255   ; CC pseudoRoom
        defb h_host & 255   ; CD walkActorToActor
        defb h3_ovb & 255   ; CE putActorAtObject
        defb h3_ovb & 255   ; CF ifState
        defb h_host & 255   ; D0 pickupObject
        defb h3_ovb & 255   ; D1 animateActor
        defb h3_ovb & 255   ; D2 actorFollowCamera
        defb h3_ovb & 255   ; D3 actorOps
        defb h3_ovb & 255   ; D4 setObjectName
        defb h3_ovb & 255   ; D5 actorFromPos
        defb h3_ovb & 255   ; D6 getActorMoving
        defb h3_or & 255   ; D7 or
        defb h3_ovb & 255   ; D8 printEgo
        defb h_host & 255   ; D9 doSentence
        defb h3_add & 255   ; DA add
        defb h3_divide & 255   ; DB divide
        defb h_host & 255   ; DC oldRoomEffect
        defb h3_ovb & 255   ; DD setClass
        defb h_host & 255   ; DE walkActorTo
        defb h_host_j & 255   ; DF isActorInBox
        defb h3_freezeScripts & 255   ; E0 freezeScripts
        defb h3_ovb & 255   ; E1 putActor
        defb h3_stopScript & 255   ; E2 stopScript
        defb h3_ovb & 255   ; E3 getActorFacing
        defb h_host & 255   ; E4 loadRoomWithEgo
        defb h_host & 255   ; E5 pickupObject
        defb h3_ovb & 255   ; E6 getClosestObjActor
        defb h3_ovb & 255   ; E7 getStringWidth
        defb h3_isScriptRunning & 255   ; E8 isScriptRunning
        defb h3_ovb & 255   ; E9 setOwnerOf
        defb h3_startScript & 255   ; EA startScript
        defb h3_debug & 255   ; EB debug
        defb h3_ovb & 255   ; EC getActorWidth
        defb h3_ovb & 255   ; ED putActorInRoom
        defb h3_stopObjectScript & 255   ; EE stopObjectScript
        defb h3_ovb & 255   ; EF ifNotState
        defb h3_ovb & 255   ; F0 lights
        defb h3_ovb & 255   ; F1 getActorCostume
        defb h_host & 255   ; F2 loadRoom
        defb h3_ovb & 255   ; F3 roomOps
        defb h3_ovb & 255   ; F4 getDist
        defb h_host_r & 255   ; F5 findObject
        defb h_host & 255   ; F6 walkActorToObject
        defb h_host & 255   ; F7 startObject
        defb h3_isGreater & 255   ; F8 isGreater
        defb h_host & 255   ; F9 doSentence
        defb h3_ovb & 255   ; FA verbOps
        defb h3_ovb & 255   ; FB getActorWalkBox
        defb h3_ovb & 255   ; FC isSoundRunning
        defb h3_ovb & 255   ; FD findInventory
        defb h_host & 255   ; FE walkActorTo
        defb h_host & 255   ; FF drawBox
disp_hi:
        defb h3_stopObjectCode / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_isGreaterEqual / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_isNotEqual / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h_host_r / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_getRandomNr / 256
        defb h3_and / 256
        defb h3_jumpRelative / 256
        defb h_host / 256
        defb h3_move / 256
        defb h3_multiply / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host_j / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_setVarRange / 256
        defb h3_ovb / 256
        defb h3_equalZero / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h3_delayVariable / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_delay / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host_r / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_isLessEqual / 256
        defb h_host / 256
        defb h3_subtract / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_cutscene / 256
        defb h3_ovb / 256
        defb h3_chainScript / 256
        defb h3_ovb / 256
        defb h3_isLess / 256
        defb h_host / 256
        defb h3_increment / 256
        defb h3_ovb / 256
        defb h3_isEqual / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h_host_r / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_or / 256
        defb h3_beginOverride / 256
        defb h_host / 256
        defb h3_add / 256
        defb h3_divide / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host_j / 256
        defb h3_freezeScripts / 256
        defb h3_ovb / 256
        defb h3_stopScript / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_isScriptRunning / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h3_debug / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_stopObjectScript / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host_r / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_isGreater / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_breakHere / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_isGreaterEqual / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_isNotEqual / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h_host_r / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_getRandomNr / 256
        defb h3_and / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_move / 256
        defb h3_multiply / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host_j / 256
        defb h3_stopObjectCode / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_setVarRange / 256
        defb h3_ovb / 256
        defb h3_notEqualZero / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h3_ovb / 256
        defb h3_expression / 256
        defb h3_ovb / 256
        defb h3_wait / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host_r / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_isLessEqual / 256
        defb h_host / 256
        defb h3_subtract / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_endCutscene / 256
        defb h3_ovb / 256
        defb h3_chainScript / 256
        defb h3_ovb / 256
        defb h3_isLess / 256
        defb h_host / 256
        defb h3_decrement / 256
        defb h3_ovb / 256
        defb h3_isEqual / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h_host_r / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_or / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_add / 256
        defb h3_divide / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host_j / 256
        defb h3_freezeScripts / 256
        defb h3_ovb / 256
        defb h3_stopScript / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_isScriptRunning / 256
        defb h3_ovb / 256
        defb h3_startScript / 256
        defb h3_debug / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_stopObjectScript / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host_r / 256
        defb h_host / 256
        defb h_host / 256
        defb h3_isGreater / 256
        defb h_host / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h3_ovb / 256
        defb h_host / 256
        defb h_host / 256
; ---- especificacion de cada opcode (0: el manejador lee sus operandos)
spec_lo:
        defb 0 & 255   ; 00 stopObjectCode
        defb 0 & 255   ; 01 putActor
        defb 0 & 255   ; 02 startMusic
        defb 0 & 255   ; 03 getActorRoom
        defb 0 & 255   ; 04 isGreaterEqual
        defb sp3_1 & 255   ; 05 drawObject
        defb 0 & 255   ; 06 getActorElevation
        defb 0 & 255   ; 07 setState
        defb 0 & 255   ; 08 isNotEqual
        defb 0 & 255   ; 09 faceActor
        defb 0 & 255   ; 0A startScript
        defb sp3_2 & 255   ; 0B getVerbEntrypoint
        defb 0 & 255   ; 0C resourceRoutines
        defb sp3_3 & 255   ; 0D walkActorToActor
        defb 0 & 255   ; 0E putActorAtObject
        defb 0 & 255   ; 0F ifState
        defb 0 & 255   ; 10 getObjectOwner
        defb 0 & 255   ; 11 animateActor
        defb 0 & 255   ; 12 panCameraTo
        defb 0 & 255   ; 13 actorOps
        defb 0 & 255   ; 14 print
        defb 0 & 255   ; 15 actorFromPos
        defb 0 & 255   ; 16 getRandomNr
        defb 0 & 255   ; 17 and
        defb 0 & 255   ; 18 jumpRelative
        defb sp3_4 & 255   ; 19 doSentence
        defb 0 & 255   ; 1A move
        defb 0 & 255   ; 1B multiply
        defb 0 & 255   ; 1C startSound
        defb 0 & 255   ; 1D ifClassOfIs
        defb sp3_5 & 255   ; 1E walkActorTo
        defb sp3_6 & 255   ; 1F isActorInBox
        defb 0 & 255   ; 20 stopMusic
        defb 0 & 255   ; 21 putActor
        defb 0 & 255   ; 22 saveLoadGame
        defb 0 & 255   ; 23 getActorY
        defb sp3_7 & 255   ; 24 loadRoomWithEgo
        defb sp3_8 & 255   ; 25 pickupObject
        defb 0 & 255   ; 26 setVarRange
        defb 0 & 255   ; 27 stringOps
        defb 0 & 255   ; 28 equalZero
        defb 0 & 255   ; 29 setOwnerOf
        defb 0 & 255   ; 2A startScript
        defb 0 & 255   ; 2B delayVariable
        defb sp3_14 & 255   ; 2C cursorCommand
        defb 0 & 255   ; 2D putActorInRoom
        defb 0 & 255   ; 2E delay
        defb 0 & 255   ; 2F ifNotState
        defb sp3_15 & 255   ; 30 setBoxFlags
        defb 0 & 255   ; 31 getInventoryCount
        defb 0 & 255   ; 32 setCameraAt
        defb sp3_21 & 255   ; 33 roomOps
        defb 0 & 255   ; 34 getDist
        defb sp3_22 & 255   ; 35 findObject
        defb sp3_23 & 255   ; 36 walkActorToObject
        defb sp3_24 & 255   ; 37 startObject
        defb 0 & 255   ; 38 isLessEqual
        defb sp3_4 & 255   ; 39 doSentence
        defb 0 & 255   ; 3A subtract
        defb sp3_11 & 255   ; 3B waitForActor
        defb 0 & 255   ; 3C stopSound
        defb 0 & 255   ; 3D findInventory
        defb sp3_5 & 255   ; 3E walkActorTo
        defb sp3_25 & 255   ; 3F drawBox
        defb 0 & 255   ; 40 cutscene
        defb 0 & 255   ; 41 putActor
        defb 0 & 255   ; 42 chainScript
        defb 0 & 255   ; 43 getActorX
        defb 0 & 255   ; 44 isLess
        defb sp3_1 & 255   ; 45 drawObject
        defb 0 & 255   ; 46 increment
        defb 0 & 255   ; 47 setState
        defb 0 & 255   ; 48 isEqual
        defb 0 & 255   ; 49 faceActor
        defb 0 & 255   ; 4A startScript
        defb sp3_2 & 255   ; 4B getVerbEntrypoint
        defb sp3_12 & 255   ; 4C waitForSentence
        defb sp3_3 & 255   ; 4D walkActorToActor
        defb 0 & 255   ; 4E putActorAtObject
        defb 0 & 255   ; 4F ifState
        defb sp3_8 & 255   ; 50 pickupObject
        defb 0 & 255   ; 51 animateActor
        defb 0 & 255   ; 52 actorFollowCamera
        defb 0 & 255   ; 53 actorOps
        defb 0 & 255   ; 54 setObjectName
        defb 0 & 255   ; 55 actorFromPos
        defb 0 & 255   ; 56 getActorMoving
        defb 0 & 255   ; 57 or
        defb 0 & 255   ; 58 beginOverride
        defb sp3_4 & 255   ; 59 doSentence
        defb 0 & 255   ; 5A add
        defb 0 & 255   ; 5B divide
        defb sp3_27 & 255   ; 5C oldRoomEffect
        defb 0 & 255   ; 5D setClass
        defb sp3_5 & 255   ; 5E walkActorTo
        defb sp3_6 & 255   ; 5F isActorInBox
        defb 0 & 255   ; 60 freezeScripts
        defb 0 & 255   ; 61 putActor
        defb 0 & 255   ; 62 stopScript
        defb 0 & 255   ; 63 getActorFacing
        defb sp3_7 & 255   ; 64 loadRoomWithEgo
        defb sp3_8 & 255   ; 65 pickupObject
        defb 0 & 255   ; 66 getClosestObjActor
        defb 0 & 255   ; 67 getStringWidth
        defb 0 & 255   ; 68 isScriptRunning
        defb 0 & 255   ; 69 setOwnerOf
        defb 0 & 255   ; 6A startScript
        defb 0 & 255   ; 6B debug
        defb 0 & 255   ; 6C getActorWidth
        defb 0 & 255   ; 6D putActorInRoom
        defb 0 & 255   ; 6E stopObjectScript
        defb 0 & 255   ; 6F ifNotState
        defb sp3_28 & 255   ; 70 lights
        defb 0 & 255   ; 71 getActorCostume
        defb sp3_11 & 255   ; 72 loadRoom
        defb sp3_21 & 255   ; 73 roomOps
        defb 0 & 255   ; 74 getDist
        defb sp3_22 & 255   ; 75 findObject
        defb sp3_23 & 255   ; 76 walkActorToObject
        defb sp3_24 & 255   ; 77 startObject
        defb 0 & 255   ; 78 isGreater
        defb sp3_4 & 255   ; 79 doSentence
        defb 0 & 255   ; 7A verbOps
        defb 0 & 255   ; 7B getActorWalkBox
        defb 0 & 255   ; 7C isSoundRunning
        defb 0 & 255   ; 7D findInventory
        defb sp3_5 & 255   ; 7E walkActorTo
        defb sp3_25 & 255   ; 7F drawBox
        defb 0 & 255   ; 80 breakHere
        defb 0 & 255   ; 81 putActor
        defb 0 & 255   ; 82 startMusic
        defb 0 & 255   ; 83 getActorRoom
        defb 0 & 255   ; 84 isGreaterEqual
        defb sp3_1 & 255   ; 85 drawObject
        defb 0 & 255   ; 86 getActorElevation
        defb 0 & 255   ; 87 setState
        defb 0 & 255   ; 88 isNotEqual
        defb 0 & 255   ; 89 faceActor
        defb 0 & 255   ; 8A startScript
        defb sp3_2 & 255   ; 8B getVerbEntrypoint
        defb 0 & 255   ; 8C resourceRoutines
        defb sp3_3 & 255   ; 8D walkActorToActor
        defb 0 & 255   ; 8E putActorAtObject
        defb 0 & 255   ; 8F ifState
        defb 0 & 255   ; 90 getObjectOwner
        defb 0 & 255   ; 91 animateActor
        defb 0 & 255   ; 92 panCameraTo
        defb 0 & 255   ; 93 actorOps
        defb 0 & 255   ; 94 print
        defb 0 & 255   ; 95 actorFromPos
        defb 0 & 255   ; 96 getRandomNr
        defb 0 & 255   ; 97 and
        defb 0 & 255   ; 98 systemOps
        defb sp3_4 & 255   ; 99 doSentence
        defb 0 & 255   ; 9A move
        defb 0 & 255   ; 9B multiply
        defb 0 & 255   ; 9C startSound
        defb 0 & 255   ; 9D ifClassOfIs
        defb sp3_5 & 255   ; 9E walkActorTo
        defb sp3_6 & 255   ; 9F isActorInBox
        defb 0 & 255   ; A0 stopObjectCode
        defb 0 & 255   ; A1 putActor
        defb 0 & 255   ; A2 saveLoadGame
        defb 0 & 255   ; A3 getActorY
        defb sp3_7 & 255   ; A4 loadRoomWithEgo
        defb sp3_8 & 255   ; A5 pickupObject
        defb 0 & 255   ; A6 setVarRange
        defb 0 & 255   ; A7 saveLoadVars
        defb 0 & 255   ; A8 notEqualZero
        defb 0 & 255   ; A9 setOwnerOf
        defb 0 & 255   ; AA startScript
        defb 0 & 255   ; AB saveRestoreVerbs
        defb 0 & 255   ; AC expression
        defb 0 & 255   ; AD putActorInRoom
        defb 0 & 255   ; AE wait
        defb 0 & 255   ; AF ifNotState
        defb sp3_15 & 255   ; B0 setBoxFlags
        defb 0 & 255   ; B1 getInventoryCount
        defb 0 & 255   ; B2 setCameraAt
        defb sp3_21 & 255   ; B3 roomOps
        defb 0 & 255   ; B4 getDist
        defb sp3_22 & 255   ; B5 findObject
        defb sp3_23 & 255   ; B6 walkActorToObject
        defb sp3_24 & 255   ; B7 startObject
        defb 0 & 255   ; B8 isLessEqual
        defb sp3_4 & 255   ; B9 doSentence
        defb 0 & 255   ; BA subtract
        defb sp3_11 & 255   ; BB waitForActor
        defb 0 & 255   ; BC stopSound
        defb 0 & 255   ; BD findInventory
        defb sp3_5 & 255   ; BE walkActorTo
        defb sp3_25 & 255   ; BF drawBox
        defb 0 & 255   ; C0 endCutscene
        defb 0 & 255   ; C1 putActor
        defb 0 & 255   ; C2 chainScript
        defb 0 & 255   ; C3 getActorX
        defb 0 & 255   ; C4 isLess
        defb sp3_1 & 255   ; C5 drawObject
        defb 0 & 255   ; C6 decrement
        defb 0 & 255   ; C7 setState
        defb 0 & 255   ; C8 isEqual
        defb 0 & 255   ; C9 faceActor
        defb 0 & 255   ; CA startScript
        defb sp3_2 & 255   ; CB getVerbEntrypoint
        defb sp3_29 & 255   ; CC pseudoRoom
        defb sp3_3 & 255   ; CD walkActorToActor
        defb 0 & 255   ; CE putActorAtObject
        defb 0 & 255   ; CF ifState
        defb sp3_8 & 255   ; D0 pickupObject
        defb 0 & 255   ; D1 animateActor
        defb 0 & 255   ; D2 actorFollowCamera
        defb 0 & 255   ; D3 actorOps
        defb 0 & 255   ; D4 setObjectName
        defb 0 & 255   ; D5 actorFromPos
        defb 0 & 255   ; D6 getActorMoving
        defb 0 & 255   ; D7 or
        defb 0 & 255   ; D8 printEgo
        defb sp3_4 & 255   ; D9 doSentence
        defb 0 & 255   ; DA add
        defb 0 & 255   ; DB divide
        defb sp3_27 & 255   ; DC oldRoomEffect
        defb 0 & 255   ; DD setClass
        defb sp3_5 & 255   ; DE walkActorTo
        defb sp3_6 & 255   ; DF isActorInBox
        defb 0 & 255   ; E0 freezeScripts
        defb 0 & 255   ; E1 putActor
        defb 0 & 255   ; E2 stopScript
        defb 0 & 255   ; E3 getActorFacing
        defb sp3_7 & 255   ; E4 loadRoomWithEgo
        defb sp3_8 & 255   ; E5 pickupObject
        defb 0 & 255   ; E6 getClosestObjActor
        defb 0 & 255   ; E7 getStringWidth
        defb 0 & 255   ; E8 isScriptRunning
        defb 0 & 255   ; E9 setOwnerOf
        defb 0 & 255   ; EA startScript
        defb 0 & 255   ; EB debug
        defb 0 & 255   ; EC getActorWidth
        defb 0 & 255   ; ED putActorInRoom
        defb 0 & 255   ; EE stopObjectScript
        defb 0 & 255   ; EF ifNotState
        defb sp3_28 & 255   ; F0 lights
        defb 0 & 255   ; F1 getActorCostume
        defb sp3_11 & 255   ; F2 loadRoom
        defb sp3_21 & 255   ; F3 roomOps
        defb 0 & 255   ; F4 getDist
        defb sp3_22 & 255   ; F5 findObject
        defb sp3_23 & 255   ; F6 walkActorToObject
        defb sp3_24 & 255   ; F7 startObject
        defb 0 & 255   ; F8 isGreater
        defb sp3_4 & 255   ; F9 doSentence
        defb 0 & 255   ; FA verbOps
        defb 0 & 255   ; FB getActorWalkBox
        defb 0 & 255   ; FC isSoundRunning
        defb 0 & 255   ; FD findInventory
        defb sp3_5 & 255   ; FE walkActorTo
        defb sp3_25 & 255   ; FF drawBox
spec_hi:
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_1 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_2 / 256
        defb 0 / 256
        defb sp3_3 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_6 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_7 / 256
        defb sp3_8 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_14 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_15 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_21 / 256
        defb 0 / 256
        defb sp3_22 / 256
        defb sp3_23 / 256
        defb sp3_24 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb sp3_11 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_25 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_1 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_2 / 256
        defb sp3_12 / 256
        defb sp3_3 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_8 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_27 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_6 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_7 / 256
        defb sp3_8 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_28 / 256
        defb 0 / 256
        defb sp3_11 / 256
        defb sp3_21 / 256
        defb 0 / 256
        defb sp3_22 / 256
        defb sp3_23 / 256
        defb sp3_24 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_25 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_1 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_2 / 256
        defb 0 / 256
        defb sp3_3 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_6 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_7 / 256
        defb sp3_8 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_15 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_21 / 256
        defb 0 / 256
        defb sp3_22 / 256
        defb sp3_23 / 256
        defb sp3_24 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb sp3_11 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_25 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_1 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_2 / 256
        defb sp3_29 / 256
        defb sp3_3 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_8 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_27 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_6 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_7 / 256
        defb sp3_8 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_28 / 256
        defb 0 / 256
        defb sp3_11 / 256
        defb sp3_21 / 256
        defb 0 / 256
        defb sp3_22 / 256
        defb sp3_23 / 256
        defb sp3_24 / 256
        defb 0 / 256
        defb sp3_4 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb 0 / 256
        defb sp3_5 / 256
        defb sp3_25 / 256
; ---- especificaciones
sp3_1:
        defb 6
        defb 7
        defb 8
        defb 0
sp3_2:
        defb 1
        defb 6
        defb 7
        defb 0
sp3_3:
        defb 3
        defb 4
        defb 9
        defb 0
sp3_4:
        defb 3
        defb 16
        defb 7
        defb 8
        defb 0
sp3_5:
        defb 3
        defb 7
        defb 8
        defb 0
sp3_6:
        defb 3
        defb 4
        defb 11
        defb 0
sp3_7:
        defb 6
        defb 4
        defb 10
        defb 10
        defb 0
sp3_8:
        defb 6
        defb 0
sp3_9:
        defb 3
        defb 4
        defb 0
sp3_10:
        defb 3
        defb 4
        defb 5
        defb 0
sp3_11:
        defb 3
        defb 0
sp3_12:
        defb 0
st3_13:   defb 15
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_9
        defw sp3_10
        defw sp3_11
        defw sp3_11
        defw sp3_9
        defw sp3_12
sp3_14:
        defb 20,$1F
        defw st3_13
        defb 0
sp3_15:
        defb 3
        defb 9
        defb 0
sp3_16:
        defb 3
        defb 4
        defb 14
        defb 3
        defb 4
        defb 14
        defb 4
        defb 0
sp3_17:
        defb 6
        defb 7
        defb 8
        defb 14
        defb 3
        defb 4
        defb 0
sp3_18:
        defb 3
        defb 13
        defb 0
sp3_19:
        defb 3
        defb 14
        defb 3
        defb 4
        defb 14
        defb 3
        defb 0
st3_20:   defb 17
        defw 0
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_16
        defw sp3_10
        defw sp3_9
        defw sp3_8
        defw sp3_17
        defw sp3_17
        defw sp3_18
        defw sp3_18
        defw sp3_19
        defw sp3_9
        defw 0
sp3_21:
        defb 6
        defb 7
        defb 20,$1F
        defw st3_20
        defb 0
sp3_22:
        defb 1
        defb 3
        defb 4
        defb 0
sp3_23:
        defb 3
        defb 7
        defb 0
sp3_24:
        defb 6
        defb 4
        defb 12
        defb 0
sp3_25:
        defb 6
        defb 7
        defb 14
        defb 6
        defb 7
        defb 5
        defb 0
st3_26:   defb 4
        defw sp3_12
        defw sp3_12
        defw sp3_12
        defw sp3_8
        defw sp3_12
sp3_27:
        defb 20,$1F
        defw st3_26
        defb 0
sp3_28:
        defb 3
        defb 9
        defb 9
        defb 0
sp3_29:
        defb 9
        defb 18
        defb 0
sp3_empty:      defb 0
