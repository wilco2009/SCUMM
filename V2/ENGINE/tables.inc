; GENERADO por SCUMM/V2/TOOLS/gen_vmtables.py: no editar a mano

; ---- especificaciones de operandos
sp_B1: defb 3,0
sp_B1_B2: defb 3,4,0
sp_B1_B2_B3: defb 3,4,5,0
sp_B1_B2_b: defb 3,4,9,0
sp_B1_S: defb 3,12,0
sp_B1_W2: defb 3,7,0
sp_B1_b: defb 3,9,0
sp_B1_b_b: defb 3,9,9,0
sp_J: defb 11,0
sp_R: defb 1,0
sp_R_B1: defb 1,3,0
sp_R_B1_B2: defb 1,3,4,0
sp_R_W1: defb 1,6,0
sp_R_W1_W2: defb 1,6,7,0
sp_R_b: defb 1,9,0
sp_R_w_B1: defb 1,10,3,0
sp_S: defb 12,0
sp_W1: defb 6,0
sp_W1_B2: defb 6,4,0
sp_W1_B2_B3: defb 6,4,5,0
sp_W1_B2_J: defb 6,4,11,0
sp_W1_B2_b_b: defb 6,4,9,9,0
sp_W1_J: defb 6,11,0
sp_W1_N: defb 6,13,0
sp_W1_b: defb 6,9,0
sp_b_b_b: defb 9,9,9,0
sp_b_w: defb 9,10,0
sp_dec_actorops:
        defb 15
        defw dec_actorops
        defb 0
sp_dec_dosentence:
        defb 15
        defw dec_dosentence
        defb 0
sp_dec_pseudoroom:
        defb 15
        defw dec_pseudoroom
        defb 0
sp_dec_verbops:
        defb 15
        defw dec_verbops
        defb 0
sp_none: defb 0
sp_setvarrange: defb 1,9,0
sp_v: defb 2,0
sp_v_J: defb 2,11,0
sp_v_W1_J: defb 2,6,11,0
sp_w_B1_B2: defb 10,3,4,0

; ---- tabla de despacho: por opcode, especificacion y manejador
disp_table:
        defw sp_none, h_o5_stopObjectCode   ; 00 o5_stopObjectCode
        defw sp_B1_B2_B3, h_o2_putActor   ; 01 o2_putActor
        defw sp_B1, h_o5_startMusic   ; 02 o5_startMusic
        defw sp_R_B1, h_o5_getActorRoom   ; 03 o5_getActorRoom
        defw sp_v_W1_J, h_o2_isGreaterEqual   ; 04 o2_isGreaterEqual
        defw sp_W1_B2_B3, h_o2_drawObject   ; 05 o2_drawObject
        defw sp_R_B1, h_o2_getActorElevation   ; 06 o2_getActorElevation
        defw sp_W1, h_o2_setStateIntrinsicOn   ; 07 o2_setStateIntrinsicOn
        defw sp_v_W1_J, h_o5_isNotEqual   ; 08 o5_isNotEqual
        defw sp_B1_W2, h_o5_faceActor   ; 09 o5_faceActor
        defw sp_R_W1, h_o2_assignVarWordIndirect   ; 0A o2_assignVarWordIndirect
        defw sp_W1_b, h_host   ; 0B o2_setObjPreposition
        defw sp_B1_b, h_host   ; 0C o2_resourceRoutines
        defw sp_B1_B2_b, h_o5_walkActorToActor   ; 0D o5_walkActorToActor
        defw sp_B1_W2, h_o2_putActorAtObject   ; 0E o2_putActorAtObject
        defw sp_W1_J, h_o2_ifStateIntrinsicOn   ; 0F o2_ifStateIntrinsicOn
        defw sp_R_W1, h_o5_getObjectOwner   ; 10 o5_getObjectOwner
        defw sp_B1_B2, h_o5_animateActor   ; 11 o5_animateActor
        defw sp_B1, h_host   ; 12 o2_panCameraTo
        defw sp_dec_actorops, h_o2_actorOps   ; 13 o2_actorOps
        defw sp_B1_S, h_o5_print   ; 14 o5_print
        defw sp_R_B1_B2, h_o2_actorFromPos   ; 15 o2_actorFromPos
        defw sp_R_B1, h_o5_getRandomNr   ; 16 o5_getRandomNr
        defw sp_W1, h_o2_setStateTouchable   ; 17 o2_setStateTouchable
        defw sp_J, h_o5_jumpRelative   ; 18 o5_jumpRelative
        defw sp_dec_dosentence, h_o2_doSentence   ; 19 o2_doSentence
        defw sp_R_W1, h_o5_move   ; 1A o5_move
        defw sp_w_B1_B2, h_o2_setBitVar   ; 1B o2_setBitVar
        defw sp_B1, h_o5_startSound   ; 1C o5_startSound
        defw sp_W1_B2_J, h_host   ; 1D o2_ifClassOfIs
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; 1E o2_walkActorTo
        defw sp_W1_J, h_o2_ifStateTouchable   ; 1F o2_ifStateTouchable
        defw sp_none, h_o5_stopMusic   ; 20 o5_stopMusic
        defw sp_B1_B2_B3, h_o2_putActor   ; 21 o2_putActor
        defw sp_R_B1, h_host_r   ; 22 o4_saveLoadGame
        defw sp_R_B1, h_o2_getActorY   ; 23 o2_getActorY
        defw sp_W1_B2_b_b, h_o2_loadRoomWithEgo   ; 24 o2_loadRoomWithEgo
        defw sp_W1_B2_B3, h_o2_drawObject   ; 25 o2_drawObject
        defw sp_setvarrange, h_o5_setVarRange   ; 26 o5_setVarRange
        defw sp_W1, h_o2_setStateLocked   ; 27 o2_setStateLocked
        defw sp_v_J, h_o5_equalZero   ; 28 o5_equalZero
        defw sp_W1_B2, h_o2_setOwnerOf   ; 29 o2_setOwnerOf
        defw sp_R_W1, h_o2_addIndirect   ; 2A o2_addIndirect
        defw sp_v, h_o5_delayVariable   ; 2B o5_delayVariable
        defw sp_R_b, h_o2_assignVarByte   ; 2C o2_assignVarByte
        defw sp_B1_B2, h_o2_putActorInRoom   ; 2D o2_putActorInRoom
        defw sp_b_b_b, h_o2_delay   ; 2E o2_delay
        defw sp_W1_J, h_o2_ifStateLocked   ; 2F o2_ifStateLocked
        defw sp_B1_b, h_o3_setBoxFlags   ; 30 o3_setBoxFlags
        defw sp_R_w_B1, h_o2_getBitVar   ; 31 o2_getBitVar
        defw sp_B1, h_host   ; 32 o2_setCameraAt
        defw sp_B1_B2_b, h_host   ; 33 o2_roomOps
        defw sp_R_W1_W2, h_o5_getDist   ; 34 o5_getDist
        defw sp_R_B1_B2, h_o2_findObject   ; 35 o2_findObject
        defw sp_B1_W2, h_o2_walkActorToObject   ; 36 o2_walkActorToObject
        defw sp_W1, h_o2_setStatePickupable   ; 37 o2_setStatePickupable
        defw sp_v_W1_J, h_o2_isLessEqual   ; 38 o2_isLessEqual
        defw sp_dec_dosentence, h_o2_doSentence   ; 39 o2_doSentence
        defw sp_R_W1, h_o2_subtract   ; 3A o2_subtract
        defw sp_B1, h_o2_waitForActor   ; 3B o2_waitForActor
        defw sp_B1, h_o5_stopSound   ; 3C o5_stopSound
        defw sp_B1_B2, h_o2_setActorElevation   ; 3D o2_setActorElevation
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; 3E o2_walkActorTo
        defw sp_W1_J, h_o2_ifStatePickupable   ; 3F o2_ifStatePickupable
        defw sp_none, h_o2_cutscene   ; 40 o2_cutscene
        defw sp_B1_B2_B3, h_o2_putActor   ; 41 o2_putActor
        defw sp_B1, h_o2_startScript   ; 42 o2_startScript
        defw sp_R_B1, h_o2_getActorX   ; 43 o2_getActorX
        defw sp_v_W1_J, h_o2_isLess   ; 44 o2_isLess
        defw sp_W1_B2_B3, h_o2_drawObject   ; 45 o2_drawObject
        defw sp_R, h_o5_increment   ; 46 o5_increment
        defw sp_W1, h_o2_setStateIntrinsicOff   ; 47 o2_setStateIntrinsicOff
        defw sp_v_W1_J, h_o5_isEqual   ; 48 o5_isEqual
        defw sp_B1_W2, h_o5_faceActor   ; 49 o5_faceActor
        defw sp_B1, h_o2_chainScript   ; 4A o2_chainScript
        defw sp_W1_b, h_host   ; 4B o2_setObjPreposition
        defw sp_none, h_o2_waitForSentence   ; 4C o2_waitForSentence
        defw sp_B1_B2_b, h_o5_walkActorToActor   ; 4D o5_walkActorToActor
        defw sp_B1_W2, h_o2_putActorAtObject   ; 4E o2_putActorAtObject
        defw sp_W1_J, h_o2_ifStateIntrinsicOff   ; 4F o2_ifStateIntrinsicOff
        defw sp_W1, h_o2_pickupObject   ; 50 o2_pickupObject
        defw sp_B1_B2, h_o5_animateActor   ; 51 o5_animateActor
        defw sp_B1, h_o5_actorFollowCamera   ; 52 o5_actorFollowCamera
        defw sp_dec_actorops, h_o2_actorOps   ; 53 o2_actorOps
        defw sp_W1_N, h_host   ; 54 o5_setObjectName
        defw sp_R_B1_B2, h_o2_actorFromPos   ; 55 o2_actorFromPos
        defw sp_R_B1, h_o5_getActorMoving   ; 56 o5_getActorMoving
        defw sp_W1, h_o2_setStateUntouchable   ; 57 o2_setStateUntouchable
        defw sp_b_w, h_o2_beginOverride   ; 58 o2_beginOverride
        defw sp_dec_dosentence, h_o2_doSentence   ; 59 o2_doSentence
        defw sp_R_W1, h_o2_add   ; 5A o2_add
        defw sp_w_B1_B2, h_o2_setBitVar   ; 5B o2_setBitVar
        defw sp_none, h_host   ; 5C o2_dummy
        defw sp_W1_B2_J, h_host   ; 5D o2_ifClassOfIs
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; 5E o2_walkActorTo
        defw sp_W1_J, h_o2_ifStateUntouchable   ; 5F o2_ifStateUntouchable
        defw sp_W1, h_o2_cursorCommand   ; 60 o2_cursorCommand
        defw sp_B1_B2_B3, h_o2_putActor   ; 61 o2_putActor
        defw sp_B1, h_o2_stopScript   ; 62 o2_stopScript
        defw sp_R_B1, h_o5_getActorFacing   ; 63 o5_getActorFacing
        defw sp_W1_B2_b_b, h_o2_loadRoomWithEgo   ; 64 o2_loadRoomWithEgo
        defw sp_W1_B2_B3, h_o2_drawObject   ; 65 o2_drawObject
        defw sp_R_W1, h_o5_getClosestObjActor   ; 66 o5_getClosestObjActor
        defw sp_W1, h_o2_setStateUnlocked   ; 67 o2_setStateUnlocked
        defw sp_R_B1, h_o5_isScriptRunning   ; 68 o5_isScriptRunning
        defw sp_W1_B2, h_o2_setOwnerOf   ; 69 o2_setOwnerOf
        defw sp_R_W1, h_o2_subIndirect   ; 6A o2_subIndirect
        defw sp_none, h_host   ; 6B o2_dummy
        defw sp_R_W1, h_o2_getObjPreposition   ; 6C o2_getObjPreposition
        defw sp_B1_B2, h_o2_putActorInRoom   ; 6D o2_putActorInRoom
        defw sp_none, h_host   ; 6E o2_dummy
        defw sp_W1_J, h_o2_ifStateUnlocked   ; 6F o2_ifStateUnlocked
        defw sp_B1_b_b, h_o2_lights   ; 70 o2_lights
        defw sp_R_B1, h_o5_getActorCostume   ; 71 o5_getActorCostume
        defw sp_B1, h_o5_loadRoom   ; 72 o5_loadRoom
        defw sp_B1_B2_b, h_host   ; 73 o2_roomOps
        defw sp_R_W1_W2, h_o5_getDist   ; 74 o5_getDist
        defw sp_R_B1_B2, h_o2_findObject   ; 75 o2_findObject
        defw sp_B1_W2, h_o2_walkActorToObject   ; 76 o2_walkActorToObject
        defw sp_W1, h_o2_setStateUnpickupable   ; 77 o2_setStateUnpickupable
        defw sp_v_W1_J, h_o2_isGreater   ; 78 o2_isGreater
        defw sp_dec_dosentence, h_o2_doSentence   ; 79 o2_doSentence
        defw sp_dec_verbops, h_host   ; 7A o2_verbOps
        defw sp_R_B1, h_o2_getActorWalkBox   ; 7B o2_getActorWalkBox
        defw sp_R_B1, h_o5_isSoundRunning   ; 7C o5_isSoundRunning
        defw sp_B1_B2, h_o2_setActorElevation   ; 7D o2_setActorElevation
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; 7E o2_walkActorTo
        defw sp_W1_J, h_o2_ifStateUnpickupable   ; 7F o2_ifStateUnpickupable
        defw sp_none, h_o5_breakHere   ; 80 o5_breakHere
        defw sp_B1_B2_B3, h_o2_putActor   ; 81 o2_putActor
        defw sp_B1, h_o5_startMusic   ; 82 o5_startMusic
        defw sp_R_B1, h_o5_getActorRoom   ; 83 o5_getActorRoom
        defw sp_v_W1_J, h_o2_isGreaterEqual   ; 84 o2_isGreaterEqual
        defw sp_W1_B2_B3, h_o2_drawObject   ; 85 o2_drawObject
        defw sp_R_B1, h_o2_getActorElevation   ; 86 o2_getActorElevation
        defw sp_W1, h_o2_setStateIntrinsicOn   ; 87 o2_setStateIntrinsicOn
        defw sp_v_W1_J, h_o5_isNotEqual   ; 88 o5_isNotEqual
        defw sp_B1_W2, h_o5_faceActor   ; 89 o5_faceActor
        defw sp_R_W1, h_o2_assignVarWordIndirect   ; 8A o2_assignVarWordIndirect
        defw sp_W1_b, h_host   ; 8B o2_setObjPreposition
        defw sp_B1_b, h_host   ; 8C o2_resourceRoutines
        defw sp_B1_B2_b, h_o5_walkActorToActor   ; 8D o5_walkActorToActor
        defw sp_B1_W2, h_o2_putActorAtObject   ; 8E o2_putActorAtObject
        defw sp_W1_J, h_o2_ifStateIntrinsicOn   ; 8F o2_ifStateIntrinsicOn
        defw sp_R_W1, h_o5_getObjectOwner   ; 90 o5_getObjectOwner
        defw sp_B1_B2, h_o5_animateActor   ; 91 o5_animateActor
        defw sp_B1, h_host   ; 92 o2_panCameraTo
        defw sp_dec_actorops, h_o2_actorOps   ; 93 o2_actorOps
        defw sp_B1_S, h_o5_print   ; 94 o5_print
        defw sp_R_B1_B2, h_o2_actorFromPos   ; 95 o2_actorFromPos
        defw sp_R_B1, h_o5_getRandomNr   ; 96 o5_getRandomNr
        defw sp_W1, h_o2_setStateTouchable   ; 97 o2_setStateTouchable
        defw sp_none, h_host   ; 98 o2_restart
        defw sp_dec_dosentence, h_o2_doSentence   ; 99 o2_doSentence
        defw sp_R_W1, h_o5_move   ; 9A o5_move
        defw sp_w_B1_B2, h_o2_setBitVar   ; 9B o2_setBitVar
        defw sp_B1, h_o5_startSound   ; 9C o5_startSound
        defw sp_W1_B2_J, h_host   ; 9D o2_ifClassOfIs
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; 9E o2_walkActorTo
        defw sp_W1_J, h_o2_ifStateTouchable   ; 9F o2_ifStateTouchable
        defw sp_none, h_o5_stopObjectCode   ; A0 o5_stopObjectCode
        defw sp_B1_B2_B3, h_o2_putActor   ; A1 o2_putActor
        defw sp_R_B1, h_host_r   ; A2 o4_saveLoadGame
        defw sp_R_B1, h_o2_getActorY   ; A3 o2_getActorY
        defw sp_W1_B2_b_b, h_o2_loadRoomWithEgo   ; A4 o2_loadRoomWithEgo
        defw sp_W1_B2_B3, h_o2_drawObject   ; A5 o2_drawObject
        defw sp_setvarrange, h_o5_setVarRange   ; A6 o5_setVarRange
        defw sp_W1, h_o2_setStateLocked   ; A7 o2_setStateLocked
        defw sp_v_J, h_o5_notEqualZero   ; A8 o5_notEqualZero
        defw sp_W1_B2, h_o2_setOwnerOf   ; A9 o2_setOwnerOf
        defw sp_R_W1, h_o2_addIndirect   ; AA o2_addIndirect
        defw sp_none, h_host   ; AB o2_switchCostumeSet
        defw sp_none, h_host   ; AC o2_drawSentence
        defw sp_B1_B2, h_o2_putActorInRoom   ; AD o2_putActorInRoom
        defw sp_none, h_o2_waitForMessage   ; AE o2_waitForMessage
        defw sp_W1_J, h_o2_ifStateLocked   ; AF o2_ifStateLocked
        defw sp_B1_b, h_o3_setBoxFlags   ; B0 o3_setBoxFlags
        defw sp_R_w_B1, h_o2_getBitVar   ; B1 o2_getBitVar
        defw sp_B1, h_host   ; B2 o2_setCameraAt
        defw sp_B1_B2_b, h_host   ; B3 o2_roomOps
        defw sp_R_W1_W2, h_o5_getDist   ; B4 o5_getDist
        defw sp_R_B1_B2, h_o2_findObject   ; B5 o2_findObject
        defw sp_B1_W2, h_o2_walkActorToObject   ; B6 o2_walkActorToObject
        defw sp_W1, h_o2_setStatePickupable   ; B7 o2_setStatePickupable
        defw sp_v_W1_J, h_o2_isLessEqual   ; B8 o2_isLessEqual
        defw sp_dec_dosentence, h_o2_doSentence   ; B9 o2_doSentence
        defw sp_R_W1, h_o2_subtract   ; BA o2_subtract
        defw sp_B1, h_o2_waitForActor   ; BB o2_waitForActor
        defw sp_B1, h_o5_stopSound   ; BC o5_stopSound
        defw sp_B1_B2, h_o2_setActorElevation   ; BD o2_setActorElevation
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; BE o2_walkActorTo
        defw sp_W1_J, h_o2_ifStatePickupable   ; BF o2_ifStatePickupable
        defw sp_none, h_o2_endCutscene   ; C0 o2_endCutscene
        defw sp_B1_B2_B3, h_o2_putActor   ; C1 o2_putActor
        defw sp_B1, h_o2_startScript   ; C2 o2_startScript
        defw sp_R_B1, h_o2_getActorX   ; C3 o2_getActorX
        defw sp_v_W1_J, h_o2_isLess   ; C4 o2_isLess
        defw sp_W1_B2_B3, h_o2_drawObject   ; C5 o2_drawObject
        defw sp_R, h_o5_decrement   ; C6 o5_decrement
        defw sp_W1, h_o2_setStateIntrinsicOff   ; C7 o2_setStateIntrinsicOff
        defw sp_v_W1_J, h_o5_isEqual   ; C8 o5_isEqual
        defw sp_B1_W2, h_o5_faceActor   ; C9 o5_faceActor
        defw sp_B1, h_o2_chainScript   ; CA o2_chainScript
        defw sp_W1_b, h_host   ; CB o2_setObjPreposition
        defw sp_dec_pseudoroom, h_host   ; CC o5_pseudoRoom
        defw sp_B1_B2_b, h_o5_walkActorToActor   ; CD o5_walkActorToActor
        defw sp_B1_W2, h_o2_putActorAtObject   ; CE o2_putActorAtObject
        defw sp_W1_J, h_o2_ifStateIntrinsicOff   ; CF o2_ifStateIntrinsicOff
        defw sp_W1, h_o2_pickupObject   ; D0 o2_pickupObject
        defw sp_B1_B2, h_o5_animateActor   ; D1 o5_animateActor
        defw sp_B1, h_o5_actorFollowCamera   ; D2 o5_actorFollowCamera
        defw sp_dec_actorops, h_o2_actorOps   ; D3 o2_actorOps
        defw sp_W1_N, h_host   ; D4 o5_setObjectName
        defw sp_R_B1_B2, h_o2_actorFromPos   ; D5 o2_actorFromPos
        defw sp_R_B1, h_o5_getActorMoving   ; D6 o5_getActorMoving
        defw sp_W1, h_o2_setStateUntouchable   ; D7 o2_setStateUntouchable
        defw sp_S, h_o5_printEgo   ; D8 o5_printEgo
        defw sp_dec_dosentence, h_o2_doSentence   ; D9 o2_doSentence
        defw sp_R_W1, h_o2_add   ; DA o2_add
        defw sp_w_B1_B2, h_o2_setBitVar   ; DB o2_setBitVar
        defw sp_none, h_host   ; DC o2_dummy
        defw sp_W1_B2_J, h_host   ; DD o2_ifClassOfIs
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; DE o2_walkActorTo
        defw sp_W1_J, h_o2_ifStateUntouchable   ; DF o2_ifStateUntouchable
        defw sp_W1, h_o2_cursorCommand   ; E0 o2_cursorCommand
        defw sp_B1_B2_B3, h_o2_putActor   ; E1 o2_putActor
        defw sp_B1, h_o2_stopScript   ; E2 o2_stopScript
        defw sp_R_B1, h_o5_getActorFacing   ; E3 o5_getActorFacing
        defw sp_W1_B2_b_b, h_o2_loadRoomWithEgo   ; E4 o2_loadRoomWithEgo
        defw sp_W1_B2_B3, h_o2_drawObject   ; E5 o2_drawObject
        defw sp_R_W1, h_o5_getClosestObjActor   ; E6 o5_getClosestObjActor
        defw sp_W1, h_o2_setStateUnlocked   ; E7 o2_setStateUnlocked
        defw sp_R_B1, h_o5_isScriptRunning   ; E8 o5_isScriptRunning
        defw sp_W1_B2, h_o2_setOwnerOf   ; E9 o2_setOwnerOf
        defw sp_R_W1, h_o2_subIndirect   ; EA o2_subIndirect
        defw sp_none, h_host   ; EB o2_dummy
        defw sp_R_W1, h_o2_getObjPreposition   ; EC o2_getObjPreposition
        defw sp_B1_B2, h_o2_putActorInRoom   ; ED o2_putActorInRoom
        defw sp_none, h_host   ; EE o2_dummy
        defw sp_W1_J, h_o2_ifStateUnlocked   ; EF o2_ifStateUnlocked
        defw sp_B1_b_b, h_o2_lights   ; F0 o2_lights
        defw sp_R_B1, h_o5_getActorCostume   ; F1 o5_getActorCostume
        defw sp_B1, h_o5_loadRoom   ; F2 o5_loadRoom
        defw sp_B1_B2_b, h_host   ; F3 o2_roomOps
        defw sp_R_W1_W2, h_o5_getDist   ; F4 o5_getDist
        defw sp_R_B1_B2, h_o2_findObject   ; F5 o2_findObject
        defw sp_B1_W2, h_o2_walkActorToObject   ; F6 o2_walkActorToObject
        defw sp_W1, h_o2_setStateUnpickupable   ; F7 o2_setStateUnpickupable
        defw sp_v_W1_J, h_o2_isGreater   ; F8 o2_isGreater
        defw sp_dec_dosentence, h_o2_doSentence   ; F9 o2_doSentence
        defw sp_dec_verbops, h_host   ; FA o2_verbOps
        defw sp_R_B1, h_o2_getActorWalkBox   ; FB o2_getActorWalkBox
        defw sp_R_B1, h_o5_isSoundRunning   ; FC o5_isSoundRunning
        defw sp_B1_B2, h_o2_setActorElevation   ; FD o2_setActorElevation
        defw sp_B1_B2_B3, h_o2_walkActorTo   ; FE o2_walkActorTo
        defw sp_W1_J, h_o2_ifStateUnpickupable   ; FF o2_ifStateUnpickupable
