#!/usr/bin/env python3
"""
Zeliard Sound Effect Ripper – FINAL FIXED
Uses OPL2 emulator with correct global volume, but no channel muting.
"""

import struct, wave, os, re, array, math

# ======================================================================
# 1. OPL2 emulator (unchanged)
# ======================================================================
class OPL2:
    def __init__(self, sample_rate):
        self.sample_rate = sample_rate
        self.reg = [0] * 256
        self.phase = [0.0] * 18
        self.sin = [math.sin(2 * math.pi * i / 1024) for i in range(1024)]

    def writeReg(self, reg, val):
        self.reg[reg & 0xFF] = val & 0xFF

    def generate(self, num_samples):
        buf = []
        for _ in range(num_samples):
            self._tick()
            s = max(-32768, min(32767, int(self.out * 32767 * 2)))
            buf.append(s)
        return buf

    def _tick(self):
        total = 0.0
        bases = [0, 1, 2, 8, 9, 0xA, 0x10, 0x11, 0x12]
        for ch in range(9):
            base = bases[ch]
            if not (self.reg[0xB0 + base] & 0x20):
                continue
            fnum = self.reg[0xA0 + base] | ((self.reg[0xB0 + base] & 0x03) << 8)
            block = (self.reg[0xB0 + base] >> 2) & 7
            freq_hz = (fnum * (2 ** block) * 49716) / (2 ** 20)
            inc = freq_hz / self.sample_rate
            op1_mult = self.reg[0x20 + base] & 0x0F or 1
            op2_mult = self.reg[0x23 + base] & 0x0F or 1
            op1_tl = self.reg[0x40 + base] & 0x3F
            op2_tl = self.reg[0x43 + base] & 0x3F
            connection = self.reg[0xC0 + base] & 1
            self.phase[ch*2]   = (self.phase[ch*2] + inc * op1_mult) % 1.0
            self.phase[ch*2+1] = (self.phase[ch*2+1] + inc * op2_mult) % 1.0
            mod = self.sin[int(self.phase[ch*2] * 1024) & 1023]
            car = self.sin[int(self.phase[ch*2+1] * 1024) & 1023]
            mod_env = (63 - op1_tl) / 63.0
            car_env = (63 - op2_tl) / 63.0
            if connection == 0:          # FM
                total += car * car_env * mod * mod_env
            else:                        # additive
                total += mod * mod_env + car * car_env * 0.5
        self.out = total / 3.0

# ======================================================================
# 2. Assembly parser (unchanged)
# ======================================================================
def extract_bytes_from_label(asm_lines, label, stop_label=None, max_count=None):
    inside = False
    data = []
    label_pat = re.compile(rf'^{re.escape(label)}\s*(:)?(?:\s+(db|dw)\b)?', re.I)
    for line in asm_lines:
        stripped = line.strip()
        if not inside:
            m = label_pat.match(stripped)
            if m: inside = True
        if not inside: continue
        if stop_label:
            if re.match(rf'^{re.escape(stop_label)}\s*(:)?\s*', stripped, re.I): break
        if re.match(r'^\w+\s*(:)?\s*$', stripped): break
        m_data = re.match(r'(?:\w+\s+)?(db|dw)\s+(.+)', stripped, re.I)
        if not m_data: break
        directive = m_data.group(1).lower()
        rest = m_data.group(2).split(';')[0]
        dup_match = re.match(r'(\S+)\s+dup\s*\(\s*(\S+)\s*\)', rest.strip(), re.I)
        if dup_match and directive == 'db':
            count_str, val_str = dup_match.groups()
            def parse_const(s):
                if s.endswith('h') or s.endswith('H'): return int(s[:-1], 16)
                if s.startswith("'") or s.startswith('"'): return ord(s[1])
                return int(s)
            data.extend([parse_const(val_str) & 0xFF] * parse_const(count_str))
            if max_count and len(data) >= max_count:
                return data[:max_count]
            continue
        tokens = re.findall(r'[^,\s]+', rest)
        is_word = (directive == 'dw')
        for tok in tokens:
            if (tok.startswith("'") and tok.endswith("'")) or (tok.startswith('"') and tok.endswith('"')):
                byte_val = ord(tok[1])
            elif re.match(r'^[0-9a-fA-F]+h$', tok):
                byte_val = int(tok[:-1], 16)
            elif re.match(r'^\d+$', tok):
                byte_val = int(tok)
            else: continue
            if is_word:
                data.append(byte_val & 0xFF)
                data.append((byte_val >> 8) & 0xFF)
            else:
                data.append(byte_val & 0xFF)
            if max_count and len(data) >= max_count:
                return data[:max_count]
    return data

def parse_asm_for_data(filename):
    with open(filename, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    sfx_block = extract_bytes_from_label(lines, 'byte_1743', stop_label='byte_2020')
    instr_block = extract_bytes_from_label(lines, 'byte_2020', max_count=81)
    freq_base_words = extract_bytes_from_label(lines, 'word_1576', max_count=12*2)
    note_scale_bytes = extract_bytes_from_label(lines, 'byte_158E', max_count=12)
    chan_base_bytes = extract_bytes_from_label(lines, 'byte_159A', max_count=9)
    return sfx_block, instr_block, freq_base_words, note_scale_bytes, chan_base_bytes

NUM_SFX = 65

# ======================================================================
# 3. OPL helpers (no mute logic, but keep global volume for realism)
# ======================================================================
MASTER_VOLUME = 0x00  # 0 = loudest, 0x3F = silent (game default full volume)

def init_opl(opl):
    for ch in range(9):
        base = CHAN_BASE[ch]
        opl.writeReg(0xA0 + base, 0)
        opl.writeReg(0xB0 + base, 0)
    opl.writeReg(0x01, 0x20)               # wave select enable
    opl.writeReg(0xBD, 0x00)
    opl.writeReg(0x07, MASTER_VOLUME)      # master volume (fade not used for SFX)

def load_instrument(opl, chan, instr_data):
    if not instr_data or len(instr_data) < 9: return
    base = CHAN_BASE[chan]
    regs = [0x20+base, 0x23+base, 0x40+base, 0x43+base,
            0x60+base, 0x63+base, 0x80+base, 0x83+base, 0xC0+base]
    for i, val in enumerate(instr_data[:9]):
        opl.writeReg(regs[i], val)

def set_channel_volume(opl, chan, volume, instruments, instrument_index):
    if instrument_index >= len(instruments): return
    instr = instruments[instrument_index]
    base = CHAN_BASE[chan]
    op1_base = instr[2] & 0x3F
    op2_base = instr[3] & 0x3F
    def calc_tl(base_tl, vol):
        return 63 - ((63 - base_tl) * vol) // 127
    opl.writeReg(0x40 + base, calc_tl(op1_base, volume))
    opl.writeReg(0x43 + base, calc_tl(op2_base, volume))

# ======================================================================
# 4. Channel sequencer (unchanged)
# ======================================================================
class ChannelPlayer:
    def __init__(self, data, start_offset, chan, global_dur_base, instruments,
                 freq_base, note_scale, opl):
        self.data = data
        self.pos = start_offset
        self.chan = chan
        self.global_dur_base = global_dur_base
        self.instruments = instruments
        self.freq_base = freq_base
        self.note_scale = note_scale
        self.opl = opl
        self.flags5 = 0
        self.duration = 0
        self.volume = 0x7F
        self.octave = 3
        self.transpose = 0
        self.note_active = False
        self.finished = False
        self.inst_index = 0

    def read_byte(self):
        if self.pos >= len(self.data): return 0
        b = self.data[self.pos]
        self.pos += 1
        return b

    def get_duration(self, index):
        addr = self.global_dur_base + index
        if 0 <= addr < len(self.data):
            return self.data[addr]
        return 1

    def tick(self):
        if self.finished: return
        if self.duration > 0:
            self.duration -= 1
            if self.duration == 0 and self.note_active:
                self.note_off()
            return
        while self.duration == 0 and not self.finished:
            cmd = self.read_byte()
            if cmd & 0x80:
                self.handle_command(cmd)
            else:
                dur_nib = (cmd >> 4) & 0xF
                note_nib = cmd & 0xF
                if note_nib in (0, 0xF):
                    self.duration = self.get_duration(dur_nib)
                    if self.note_active:
                        self.note_off()
                else:
                    self.play_note(note_nib, dur_nib)

    def note_off(self):
        base = CHAN_BASE[self.chan]
        self.opl.writeReg(0xB0 + base, 0)
        self.note_active = False

    def play_note(self, note, dur_nib):
        idx = note - 1
        if idx < 0 or idx >= 12: return
        fnum = self.freq_base[idx] + self.transpose
        set_channel_volume(self.opl, self.chan, self.volume,
                           self.instruments, self.inst_index)
        base = CHAN_BASE[self.chan]
        fnum_low = fnum & 0xFF
        fnum_high = ((fnum >> 8) & 0x3) | ((self.octave & 7) << 2) | 0x20
        self.opl.writeReg(0xA0 + base, fnum_low)
        self.opl.writeReg(0xB0 + base, fnum_high)
        self.note_active = True
        self.duration = self.get_duration(dur_nib)

    def handle_command(self, cmd):
        if 0x80 <= cmd <= 0xBF:
            self.inst_index = cmd & 0x3F
            if self.inst_index < len(self.instruments):
                load_instrument(self.opl, self.chan, self.instruments[self.inst_index])
        elif 0xD0 <= cmd <= 0xD7:
            self.octave = cmd & 7
        elif 0xE0 <= cmd <= 0xFF:
            sub = cmd & 0x1F
            if sub == 0: self.read_byte()
            elif sub == 1: self.transpose = self.read_byte()
            elif sub == 2:
                self.flags5 &= ~0x40
                if self.read_byte():
                    self.flags5 |= 0x40
                    for _ in range(4): self.read_byte()
            elif sub == 3: self.octave = max(0, self.octave - 1)
            elif sub == 4: self.octave = min(7, self.octave + 1)
            elif sub == 5:
                self.volume = self.read_byte()
                set_channel_volume(self.opl, self.chan, self.volume,
                                   self.instruments, self.inst_index)
            elif sub == 0x10:
                idx = self.read_byte()
                self.global_dur_base += idx * 8
            elif sub == 0x1F: self.finished = True

# ======================================================================
# 5. Rendering
# ======================================================================
def render_all(sfx_block, instr_block, freq_base, note_scale, chan_base,
               sample_rate=44100, tick_rate=140):
    headers = [sfx_block[i:i+7] for i in range(0, NUM_SFX*7, 7)]
    note_stream = sfx_block[NUM_SFX*7:]
    instruments = [instr_block[i:i+9] for i in range(0, min(81, len(instr_block)), 9)]
    if not instruments: return []

    wav_outputs = []
    base_data_addr = 0x1743
    samples_per_tick = sample_rate // tick_rate

    for idx, hdr in enumerate(headers):
        ch1_ptr = hdr[1] | (hdr[2] << 8)
        ch2_ptr = hdr[3] | (hdr[4] << 8)
        global_word = hdr[5] | (hdr[6] << 8)
        if ch1_ptr == 0 or ch2_ptr == 0: continue
        off1 = ch1_ptr - base_data_addr - NUM_SFX*7
        off2 = ch2_ptr - base_data_addr - NUM_SFX*7
        global_dur_off = global_word - base_data_addr - NUM_SFX*7
        if (off1<0 or off2<0 or off1>=len(note_stream) or off2>=len(note_stream) or
            global_dur_off<0 or global_dur_off>=len(note_stream)): continue

        opl = OPL2(sample_rate)
        init_opl(opl)

        ch1 = ChannelPlayer(note_stream, off1, 4, global_dur_off,
                            instruments, freq_base, note_scale, opl)
        ch2 = ChannelPlayer(note_stream, off2, 5, global_dur_off,
                            instruments, freq_base, note_scale, opl)

        all_samples = []
        for _ in range(4000):
            ch1.tick()
            ch2.tick()
            all_samples.extend(opl.generate(samples_per_tick))
            if ch1.finished and ch2.finished:
                break

        if all_samples:
            maxv = max(max(all_samples), -min(all_samples))
            if idx == 0:
                print(f"Effect 0 max amplitude: {maxv}")
            if maxv > 0 and maxv < 500:
                factor = 32767 // maxv
                all_samples = [int(s * factor) for s in all_samples]
            raw = struct.pack('<' + 'h' * len(all_samples), *all_samples)
            wav_outputs.append((idx, raw))
        else:
            print(f"Effect {idx}: no output")

    return wav_outputs

def write_wav(filename, data, sample_rate=44100, channels=1, sampwidth=2):
    with wave.open(filename, 'wb') as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sampwidth)
        wf.setframerate(sample_rate)
        wf.writeframes(data)

def main():
    # Self‑test
    def self_test():
        opl = OPL2(44100)
        opl.writeReg(0x01, 0x20)
        opl.writeReg(0xBD, 0x00)
        opl.writeReg(0x20, 0x01)
        opl.writeReg(0x23, 0x01)
        opl.writeReg(0x40, 0x3F)
        opl.writeReg(0x43, 0x00)
        opl.writeReg(0xC0, 0x01)    # additive
        opl.writeReg(0xA0, 0x56)
        opl.writeReg(0xB0, 0x20 | (4<<2) | 0x01)
        samples = opl.generate(2000)
        return max(samples) > 1000

    if not self_test():
        print("OPL2 self‑test failed. Aborting.")
        return

    asm_file = 'sndadlib.asm'
    if not os.path.exists(asm_file):
        print(f"File {asm_file} not found.")
        return
    sfx_block, instr_block, freq_words, note_scale, chan_base = parse_asm_for_data(asm_file)
    if not sfx_block or len(sfx_block) < NUM_SFX*7:
        print(f"Not enough SFX data. Got {len(sfx_block)} bytes.")
        return
    global FREQ_BASE, NOTE_SCALE, CHAN_BASE
    if len(freq_words) < 24:
        print("Frequency table too short.")
        return
    FREQ_BASE = [freq_words[i] | (freq_words[i+1]<<8) for i in range(0,24,2)]
    NOTE_SCALE = note_scale[:12]
    CHAN_BASE = chan_base[:9]

    print(f"Extracted {len(sfx_block)} bytes SFX block, {len(instr_block)} bytes instruments.")
    wavs = render_all(sfx_block, instr_block, FREQ_BASE, NOTE_SCALE, CHAN_BASE)
    if not wavs:
        print("No sound effects rendered.")
        return
    os.makedirs('sfx_wav', exist_ok=True)
    for idx, wav_data in wavs:
        fname = f'sfx_wav/effect_{idx:02d}.wav'
        write_wav(fname, wav_data)
        print(f"Saved {fname}")
    print(f"Rendered {len(wavs)} effects.")

if __name__ == '__main__':
    main()