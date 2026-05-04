from types import SimpleNamespace

from yime.input_method.ui.manual_input_resolver import ManualInputResolver


def test_normalize_event_physical_key_prefers_vk_for_altgr_output() -> None:
    event = SimpleNamespace(keysym="\U00100038", keycode=0x4A)

    assert ManualInputResolver.normalize_event_physical_key(event) == "j"


def test_normalize_event_physical_key_uses_oem_vk_mapping() -> None:
    event = SimpleNamespace(keysym="bracketleft", keycode=0xDB)

    assert ManualInputResolver.normalize_event_physical_key(event) == "["


def test_normalize_event_physical_key_falls_back_to_keysym() -> None:
    event = SimpleNamespace(keysym="K", keycode=0)

    assert ManualInputResolver.normalize_event_physical_key(event) == "k"
