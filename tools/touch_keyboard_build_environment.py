"""Process-local Go settings shared by the x64 and ARM64 18u builders."""
import os


def build_environment(architecture, inherited=None):
    if architecture not in ('amd64', 'arm64'):
        raise ValueError('desktop frontend requires amd64 or arm64')
    env = dict(os.environ if inherited is None else inherited)
    if env.get('GOFLAGS', '').strip():
        raise ValueError('18u build requires empty inherited GOFLAGS; source overlays and alternate build flags are refused')
    # A clean Git checkout cannot attest sources substituted by -overlay or an
    # external workspace. Do not read persisted Go settings or mutate them.
    env.update(GOENV='off', GOFLAGS='', GOWORK='off', GOTOOLCHAIN='local',
               GOOS='windows', GOARCH=architecture, CGO_ENABLED='0')
    return env
