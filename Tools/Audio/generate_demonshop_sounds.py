"""DemonShop physical acoustic sound synthesis script.
Strictly adheres to .agents/skills/roblox-audio-workflow specifications:
- ADSR envelope on all signals (zero pop/click)
- True peak headroom <= -1.0 dBFS
- 44100 Hz 16-bit PCM MP3 via lameenc
- 3D spatial sounds in Mono (1 channel)
- 2D UI / Reward sounds in Stereo (2 channels) or Mono
"""
import math
from pathlib import Path
import lameenc
import numpy as np

SAMPLE_RATE = 44100
HEADROOM_DB = -1.0
MAX_AMP = 10 ** (HEADROOM_DB / 20.0)  # ~0.891


def apply_adsr(signal: np.ndarray, sample_rate: int,
               attack: float = 0.005, decay: float = 0.05,
               sustain: float = 0.7, release: float = 0.05) -> np.ndarray:
    n_samples = len(signal)
    envelope = np.zeros(n_samples, dtype=np.float64)

    n_attack = max(1, int(attack * sample_rate))
    n_decay = max(1, int(decay * sample_rate))
    n_release = max(1, int(release * sample_rate))
    n_sustain = max(0, n_samples - n_attack - n_decay - n_release)

    idx = 0
    # 1. Attack
    end_atk = min(idx + n_attack, n_samples)
    envelope[idx:end_atk] = np.linspace(0.0, 1.0, end_atk - idx)
    idx = end_atk

    # 2. Decay
    if idx < n_samples and n_decay > 0:
        end_dec = min(idx + n_decay, n_samples)
        envelope[idx:end_dec] = np.linspace(1.0, sustain, end_dec - idx)
        idx = end_dec

    # 3. Sustain
    if idx < n_samples and n_sustain > 0:
        end_sus = min(idx + n_sustain, n_samples)
        envelope[idx:end_sus] = sustain
        idx = end_sus

    # 4. Release
    if idx < n_samples:
        envelope[idx:] = np.linspace(sustain, 0.0, n_samples - idx)

    return signal * envelope


def export_mp3(data: np.ndarray, sample_rate: int, channels: int, out_path: Path):
    peak = np.max(np.abs(data))
    if peak > 0:
        norm = (data / peak) * MAX_AMP
    else:
        norm = data

    pcm_int16 = (np.clip(norm, -1.0, 1.0) * 32767).astype(np.int16)

    encoder = lameenc.Encoder()
    encoder.set_bit_rate(128)
    encoder.set_in_sample_rate(sample_rate)
    encoder.set_channels(channels)
    encoder.set_quality(2)

    if channels == 2 and pcm_int16.ndim == 1:
        pcm_stereo = np.column_stack((pcm_int16, pcm_int16))
        mp3_data = encoder.encode(pcm_stereo.tobytes()) + encoder.flush()
    else:
        mp3_data = encoder.encode(pcm_int16.tobytes()) + encoder.flush()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(mp3_data)


def synth_uiclick(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.08
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    freq = np.linspace(2200, 600, len(t))
    sine = np.sin(2 * np.pi * freq * t)
    np.random.seed(42)
    noise = (np.random.rand(len(t)) * 2 - 1) * np.exp(-120 * t)
    sig = sine * 0.7 + noise * 0.3
    return apply_adsr(sig, sr, attack=0.001, decay=0.015, sustain=0.1, release=0.03), 1


def synth_uiopen(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.22
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    freq = np.linspace(350, 850, len(t))
    sine = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 1.5 * t)
    np.random.seed(43)
    noise = (np.random.rand(len(t)) * 2 - 1) * 0.15
    sig = sine * 0.85 + noise
    return apply_adsr(sig, sr, attack=0.02, decay=0.06, sustain=0.6, release=0.08), 2


def synth_uiclose(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.18
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    freq = np.linspace(800, 320, len(t))
    sine = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 0.5 * t)
    np.random.seed(44)
    noise = (np.random.rand(len(t)) * 2 - 1) * 0.1
    sig = sine * 0.9 + noise
    return apply_adsr(sig, sr, attack=0.01, decay=0.05, sustain=0.5, release=0.06), 2


def synth_hitimpact(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.22
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    freq = np.linspace(150, 45, len(t))
    thump = np.sin(2 * np.pi * freq * t) * np.exp(-22 * t)
    np.random.seed(45)
    flesh_noise = (np.random.rand(len(t)) * 2 - 1) * np.exp(-35 * t)
    sig = np.tanh((thump * 1.4 + flesh_noise * 0.6) * 1.2)
    return apply_adsr(sig, sr, attack=0.002, decay=0.05, sustain=0.3, release=0.08), 1


def synth_bodystun(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.45
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    impact = np.sin(2 * np.pi * np.linspace(110, 35, len(t)) * t) * np.exp(-15 * t)
    daze_mod = np.sin(2 * np.pi * 8 * t) * 0.4
    daze_tone = np.sin(2 * np.pi * 480 * t + daze_mod) * np.exp(-6 * t) * 0.35
    np.random.seed(46)
    noise = (np.random.rand(len(t)) * 2 - 1) * np.exp(-20 * t) * 0.4
    sig = impact * 0.6 + daze_tone + noise
    return apply_adsr(sig, sr, attack=0.003, decay=0.08, sustain=0.4, release=0.15), 1


def synth_bodypickup(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.28
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    lift = np.sin(2 * np.pi * np.linspace(120, 220, len(t)) * t) * 0.5
    np.random.seed(47)
    cloth = (np.random.rand(len(t)) * 2 - 1) * np.sin(np.pi * (t / duration)) * 0.5
    sig = lift + cloth
    return apply_adsr(sig, sr, attack=0.02, decay=0.06, sustain=0.5, release=0.08), 1


def synth_bodydrop(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.32
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    thud1 = np.sin(2 * np.pi * 65 * t) * np.exp(-20 * t)
    bounce_start = int(0.08 * sr)
    thud2 = np.zeros_like(t)
    if bounce_start < len(t):
        tb = t[bounce_start:] - t[bounce_start]
        thud2[bounce_start:] = np.sin(2 * np.pi * 55 * tb) * np.exp(-25 * tb) * 0.35
    np.random.seed(48)
    dust = (np.random.rand(len(t)) * 2 - 1) * np.exp(-28 * t) * 0.3
    sig = thud1 + thud2 + dust
    return apply_adsr(sig, sr, attack=0.003, decay=0.08, sustain=0.3, release=0.12), 1


def synth_pooldeposit(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.48
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    plop = np.sin(2 * np.pi * np.linspace(120, 50, len(t)) * t) * np.exp(-14 * t)
    np.random.seed(49)
    bubbles = np.zeros_like(t)
    for _ in range(12):
        onset = np.random.uniform(0.02, 0.28)
        bfreq = np.random.uniform(600, 2200)
        idx = int(onset * sr)
        if idx < len(t):
            sub_t = t[idx:] - onset
            bubbles[idx:] += np.sin(2 * np.pi * bfreq * sub_t) * np.exp(-50 * sub_t) * 0.15
    splash_noise = (np.random.rand(len(t)) * 2 - 1) * np.exp(-12 * t) * 0.3
    sig = plop * 0.5 + bubbles * 0.4 + splash_noise * 0.3
    return apply_adsr(sig, sr, attack=0.005, decay=0.10, sustain=0.4, release=0.18), 1


def synth_poolretrieve(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.38
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    suction = np.sin(2 * np.pi * np.linspace(220, 480, len(t)) * t) * np.exp(-10 * t) * 0.4
    np.random.seed(50)
    drips = np.zeros_like(t)
    for onset in [0.08, 0.16, 0.24, 0.30]:
        dfreq = np.random.uniform(1400, 2600)
        idx = int(onset * sr)
        if idx < len(t):
            sub_t = t[idx:] - onset
            drips[idx:] += np.sin(2 * np.pi * dfreq * sub_t) * np.exp(-60 * sub_t) * 0.2
    water = (np.random.rand(len(t)) * 2 - 1) * np.exp(-15 * t) * 0.25
    sig = suction + drips + water
    return apply_adsr(sig, sr, attack=0.01, decay=0.07, sustain=0.4, release=0.12), 1


def synth_paintstroke(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.16
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    vibrato = np.sin(2 * np.pi * 25 * t) * 0.3
    magic = np.sin(2 * np.pi * 1200 * t + vibrato) * 0.3
    np.random.seed(51)
    brush = (np.random.rand(len(t)) * 2 - 1) * 0.4
    sig = magic + brush
    return apply_adsr(sig, sr, attack=0.015, decay=0.04, sustain=0.6, release=0.05), 1


def synth_paintcomplete(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.65
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    # Tri-tone magical chime A5 (880), E6 (1320), A6 (1760)
    split1 = int(0.12 * sr)
    split2 = int(0.24 * sr)
    sig = np.zeros_like(t)
    sig[:split1] = np.sin(2 * np.pi * 880 * t[:split1]) + 0.3 * np.sin(2 * np.pi * 1760 * t[:split1])
    sig[split1:split2] = np.sin(2 * np.pi * 1320 * t[split1:split2]) + 0.3 * np.sin(2 * np.pi * 2640 * t[split1:split2])
    sig[split2:] = np.sin(2 * np.pi * 1760 * t[split2:]) + 0.4 * np.sin(2 * np.pi * 3520 * t[split2:])
    decay = np.exp(-5.5 * t)
    return apply_adsr(sig * decay, sr, attack=0.005, decay=0.10, sustain=0.5, release=0.25), 2


def synth_altarplace(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.30
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    stone = np.sin(2 * np.pi * np.linspace(130, 70, len(t)) * t) * np.exp(-18 * t)
    sub = np.sin(2 * np.pi * 60 * t) * np.exp(-12 * t) * 0.4
    np.random.seed(52)
    friction = (np.random.rand(len(t)) * 2 - 1) * np.exp(-25 * t) * 0.3
    sig = stone * 0.6 + sub + friction
    return apply_adsr(sig, sr, attack=0.005, decay=0.07, sustain=0.4, release=0.12), 1


def synth_altarloop(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 2.50
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    # Slow breathing modulation 0.4 Hz
    amp_mod = 0.7 + 0.3 * np.sin(2 * np.pi * 0.4 * t)
    freq_mod = np.sin(2 * np.pi * 2.0 * t) * 0.5
    f1 = np.sin(2 * np.pi * 55 * t) * 0.5
    f2 = np.sin(2 * np.pi * 110 * t + freq_mod) * 0.35
    f3 = np.sin(2 * np.pi * 165 * t) * 0.2
    dark_hum = (f1 + f2 + f3) * amp_mod
    # Crossfade envelope to ensure seamless loop
    fade_len = int(0.25 * sr)
    fade_in = np.linspace(0.0, 1.0, fade_len)
    fade_out = np.linspace(1.0, 0.0, fade_len)
    env = np.ones_like(t)
    env[:fade_len] = fade_in
    env[-fade_len:] = fade_out
    return dark_hum * env, 1


def synth_altarcomplete(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.75
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    # Buildup then burst
    burst_idx = int(0.18 * sr)
    sig = np.zeros_like(t)
    # Buildup sweep
    tb = t[:burst_idx]
    sig[:burst_idx] = np.sin(2 * np.pi * np.linspace(120, 600, len(tb)) * tb) * (tb / 0.18) * 0.5
    # Arcane burst
    tc = t[burst_idx:] - t[burst_idx]
    burst_sub = np.sin(2 * np.pi * np.linspace(250, 60, len(tc)) * tc) * np.exp(-12 * tc) * 0.7
    crystal = (np.sin(2 * np.pi * 2400 * tc) + 0.4 * np.sin(2 * np.pi * 4800 * tc)) * np.exp(-16 * tc) * 0.5
    np.random.seed(53)
    burst_noise = (np.random.rand(len(tc)) * 2 - 1) * np.exp(-20 * tc) * 0.4
    sig[burst_idx:] = burst_sub + crystal + burst_noise
    return apply_adsr(sig, sr, attack=0.008, decay=0.12, sustain=0.4, release=0.30), 1


def synth_potionpickup(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.22
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    glass1 = np.sin(2 * np.pi * 2850 * t) * np.exp(-32 * t)
    glass2 = np.sin(2 * np.pi * 5700 * t) * np.exp(-45 * t) * 0.35
    sig = glass1 + glass2
    return apply_adsr(sig, sr, attack=0.001, decay=0.04, sustain=0.2, release=0.10), 1


def synth_coinreward(sr=SAMPLE_RATE) -> tuple[np.ndarray, int]:
    duration = 0.55
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    # Classic arcade double chime
    split = int(0.08 * sr)
    coin_chime = np.zeros_like(t)
    coin_chime[:split] = np.sin(2 * np.pi * 987.77 * t[:split]) + 0.3 * np.sin(2 * np.pi * 1975.5 * t[:split])
    coin_chime[split:] = (np.sin(2 * np.pi * 1318.51 * t[split:]) + 0.4 * np.sin(2 * np.pi * 2637.0 * t[split:])) * np.exp(-7.0 * t[split:])
    # 3 secondary metallic clinks in pouch
    np.random.seed(54)
    clinks = np.zeros_like(t)
    for onset in [0.12, 0.22, 0.32]:
        cfreq = np.random.uniform(3200, 4800)
        idx = int(onset * sr)
        if idx < len(t):
            sub_t = t[idx:] - onset
            clinks[idx:] += np.sin(2 * np.pi * cfreq * sub_t) * np.exp(-75 * sub_t) * 0.25
    sig = coin_chime * 0.75 + clinks * 0.35
    return apply_adsr(sig, sr, attack=0.003, decay=0.10, sustain=0.5, release=0.22), 2


SYNTHESIZERS = {
    "UIClick": synth_uiclick,
    "UIOpen": synth_uiopen,
    "UIClose": synth_uiclose,
    "HitImpact": synth_hitimpact,
    "BodyStun": synth_bodystun,
    "BodyPickup": synth_bodypickup,
    "BodyDrop": synth_bodydrop,
    "PoolDeposit": synth_pooldeposit,
    "PoolRetrieve": synth_poolretrieve,
    "PaintStroke": synth_paintstroke,
    "PaintComplete": synth_paintcomplete,
    "AltarPlace": synth_altarplace,
    "AltarLoop": synth_altarloop,
    "AltarComplete": synth_altarcomplete,
    "PotionPickup": synth_potionpickup,
    "CoinReward": synth_coinreward,
}


def main():
    root = Path(__file__).resolve().parents[2]
    out_dir = root / "Assets" / "Sounds"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Synthesizing {len(SYNTHESIZERS)} DemonShop sound effects to {out_dir}...")
    for name, func in SYNTHESIZERS.items():
        data, channels = func()
        out_path = out_dir / f"{name}.mp3"
        export_mp3(data, SAMPLE_RATE, channels, out_path)
        peak = np.max(np.abs(data))
        duration = len(data) / SAMPLE_RATE
        print(f"  [OK] {name:<14} -> {out_path.name:<18} (channels={channels}, duration={duration:.2f}s, size={out_path.stat().st_size} bytes)")

    print("All sound effects synthesized successfully!")


if __name__ == "__main__":
    main()
