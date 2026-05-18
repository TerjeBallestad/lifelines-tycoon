extends Node

const ELLING_INIT_PATH := "res://features/client/elling_init.tres"

var client: ClientState
var case_file: CaseFile
var economy: EconomyState
var decay: ClientDecay

func _ready() -> void:
    reset_for_test()

func reset_for_test() -> void:
    client = ClientState.new()
    var init: ClientInitData = load(ELLING_INIT_PATH) as ClientInitData
    if init != null:
        client.apply_init_data(init)
    else:
        # fallback for tests that run before content lands
        client.id = &"elling"
        client.display_name = "Elling Pettersen"
    case_file = CaseFile.new()
    economy = EconomyState.new()
    decay = ClientDecay.new()
