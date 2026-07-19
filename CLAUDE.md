# Claude Instructions — hibernate-guard

กฎเฉพาะโปรเจคนี้ (กฎร่วมอยู่ที่ `dev/CLAUDE.md` + `~/.claude/CLAUDE.md`)

## สิ่งที่ต้องรู้ก่อนแก้โค้ด

- **PowerShell 5.1 เท่านั้น** — ห้ามใช้ ternary, `??`, `?.`, pipeline chain `&&`/`||`
- Runtime จริงอยู่ที่ `%LOCALAPPDATA%\HibernateGuard` — แก้โค้ดใน repo แล้วต้องรัน `install.ps1` ซ้ำถึงจะมีผล (ยกเว้น `config.json` ที่ installer จะไม่ทับของเดิม)
- `install.ps1`/`uninstall.ps1` แตะ `~/.claude/settings.json` — แก้ logic ส่วนนี้ต้องระวังไม่ทับ hooks อื่น (มี Obsidian git-push hook อยู่ใน `Stop`)
- การทดสอบ watcher ใช้ `-SimulateIdleSeconds` + `-CountdownOverrideSeconds` (ดู README)
- Scheduled task ชื่อ `HibernateGuard` — `-MultipleInstances IgnoreNew` สำคัญ อย่าเอาออก (กัน instance ซ้อนตอน countdown)

## Pending / Known issues

- **dryRun ยังเปิดอยู่** — รอ Ice ทดสอบ 1 คืนแล้วค่อยตั้ง `dryRun: false` ใน `%LOCALAPPDATA%\HibernateGuard\config.json`
- Hooks มีผลเฉพาะ Claude Code session ที่เปิดใหม่หลังติดตั้ง — session ที่เปิดค้างก่อนติดตั้งจะไม่สร้าง busy flag
- Background task (`run_in_background`) ไม่ถูกนับเป็น busy — by design (ยอมรับแล้ว)
