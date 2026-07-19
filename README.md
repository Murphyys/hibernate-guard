# HibernateGuard

Hibernate เครื่อง Windows อัตโนมัติเมื่อ **Claude Code ทำงานเสร็จแล้ว** และ **ไม่มีการใช้ mouse/keyboard นานเกินกำหนด** — แก้ปัญหาเปิดคอมทิ้งไว้ทั้งคืนเพราะเผลอหลับระหว่างรอ Claude รันงานยาวๆ

## เงื่อนไขการ hibernate (ต้องผ่านทุกข้อ)

1. ไม่มี Claude Code session ไหนกำลังตอบอยู่ (ตรวจผ่าน hook — main turn จบแล้ว)
2. Mouse/keyboard idle ≥ 30 นาที (ปรับได้ใน `config.json`)
3. ไม่ได้กด pause (ไม่มี `paused.flag`)
4. ผ่าน popup countdown 90 วินาที (ขยับเมาส์หรือกด Cancel = ยกเลิก)

## วิธีทำงาน

```
Claude Code hooks                          Task Scheduler (ทุก 1 นาที)
  UserPromptSubmit → สร้าง busy/<sid>.flag    watcher.ps1:
  Stop/SessionEnd  → ลบ flag                   paused? → ข้าม
                                               busy/ มี flag สด? → ข้าม
                                               idle < 30 นาที? → ข้าม
                                               → popup countdown 90 วิ
                                               → เช็คซ้ำ → shutdown /h
```

- Flag ที่ค้างเกิน 6 ชม. (session crash โดยไม่ยิง Stop) ถือว่า stale — ลบทิ้งอัตโนมัติ
- ทุกอย่างติดตั้งที่ `%LOCALAPPDATA%\HibernateGuard` (log อยู่ที่นั่นด้วย: `watcher.log`)

## ติดตั้ง

```powershell
.\install.ps1
```

ไม่ต้องใช้สิทธิ์ admin ตัว installer จะ:
- copy สคริปต์ไป `%LOCALAPPDATA%\HibernateGuard`
- ลง scheduled task `HibernateGuard` (รันทุก 1 นาที แบบซ่อนหน้าต่าง)
- เพิ่ม hooks เข้า `~/.claude/settings.json` (backup ไว้ที่ `settings.json.hibernateguard.bak` — hooks มีผลกับ session ใหม่เท่านั้น)
- สร้าง desktop shortcut **"Hibernate Guard Toggle"** สำหรับ pause/resume
- เตือนถ้าเครื่องปิด hibernate อยู่ (`powercfg /hibernate on` แบบ admin เพื่อเปิด)

> **ค่าเริ่มต้นคือ DRY-RUN** — ระบบจะ log ว่า "จะ hibernate" แต่ไม่ทำจริง ทดสอบจนพอใจแล้วค่อยแก้ `dryRun: false` ใน `%LOCALAPPDATA%\HibernateGuard\config.json`

## Config (`config.json`)

| key | default | ความหมาย |
|---|---|---|
| `idleMinutes` | 30 | idle กี่นาทีถึงเริ่มพิจารณา hibernate |
| `countdownSeconds` | 90 | เวลานับถอยหลังใน popup ก่อน hibernate จริง |
| `staleFlagHours` | 6 | busy flag เก่ากว่านี้ถือว่า stale (session crash) |
| `dryRun` | true | `true` = log อย่างเดียว ไม่ hibernate จริง |

แก้ config ที่ `%LOCALAPPDATA%\HibernateGuard\config.json` (มีผลรอบเช็คถัดไปทันที ไม่ต้อง restart อะไร)

## ทดสอบ (มี test switch ในตัว)

```powershell
# จำลอง idle 1 ชม. + countdown 5 วิ (dry-run) — popup ขึ้นจริง แต่แค่ log
powershell -File "$env:LOCALAPPDATA\HibernateGuard\watcher.ps1" -SimulateIdleSeconds 3600 -CountdownOverrideSeconds 5
```

## ถอนการติดตั้ง

```powershell
.\uninstall.ps1
```

ลบ task + hooks + shortcut + โฟลเดอร์ติดตั้งทั้งหมด

## ข้อจำกัดที่รู้อยู่แล้ว

- Background task ของ Claude Code (`run_in_background`) ที่ยังรันต่อหลัง main turn จบ จะไม่ถูกนับเป็น busy — ออกแบบไว้ว่า 30 นาที idle เพียงพอให้งานพวกนั้นเสร็จ
- Hook เพิ่ม latency ~0.3–0.5 วิ ตอนส่ง prompt (powershell startup)
- ถ้า Claude ค้างรอ permission approval กลางคัน flag จะค้างจนกว่าจะครบ `staleFlagHours`
