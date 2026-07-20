# Claude Instructions — hibernate-guard

กฎเฉพาะโปรเจคนี้ (กฎร่วมอยู่ที่ `dev/CLAUDE.md` + `~/.claude/CLAUDE.md`)

## สิ่งที่ต้องรู้ก่อนแก้โค้ด

- **PowerShell 5.1 เท่านั้น** — ห้ามใช้ ternary, `??`, `?.`, pipeline chain `&&`/`||`
- Runtime จริงอยู่ที่ `%LOCALAPPDATA%\HibernateGuard` — แก้โค้ดใน repo แล้วต้องรัน `install.ps1` ซ้ำถึงจะมีผล (ยกเว้น `config.json` ที่ installer จะไม่ทับของเดิม)
- `install.ps1`/`uninstall.ps1` แตะ `~/.claude/settings.json` — แก้ logic ส่วนนี้ต้องระวังไม่ทับ hooks อื่น (มี Obsidian git-push hook อยู่ใน `Stop`)
- การทดสอบ watcher ใช้ `-SimulateIdleSeconds` + `-CountdownOverrideSeconds` (ดู README)
- Scheduled task ชื่อ `HibernateGuard` — `-MultipleInstances IgnoreNew` สำคัญ อย่าเอาออก (กัน instance ซ้อนตอน countdown)

## Pending / Known issues

- **dryRun = false แล้ว (2026-07-20)** — armed จริงแล้ว; ถ้าต้องการ pause ใช้ `toggle.ps1` หรือสร้าง `paused.flag` ใน runtime dir
- Hooks มีผลเฉพาะ Claude Code session ที่เปิดใหม่หลังติดตั้ง — session ที่เปิดค้างก่อนติดตั้งจะไม่สร้าง busy flag
- Background task (`run_in_background`) ไม่ถูกนับเป็น busy — by design (ยอมรับแล้ว)
- **2026-07-20 แก้บั๊ก:** stale-flag cleanup เดิมอยู่ใน `Test-Busy` ซึ่งถูกเรียกก็ต่อเมื่อ idle ผ่าน 30 นาทีแล้ว — ถ้าเครื่อง active ทั้งวัน flag จาก session ที่ crash/ปิดกลางคันจะไม่เคยถูกกวาดเลย แก้โดยแยก `Remove-StaleFlags` ออกมารันทุก pass ไม่ต้องรอ idle (ดู `watcher.ps1`)
- **สังเกตจริง:** เครื่อง Ice มี `claude.exe` process รันพร้อมกันได้เยอะมาก (~14 ตัวตอนตรวจ) จาก MCP/scheduled task ต่างๆ (เช่น todo→Obsidian sync) — busy-check จะบล็อก hibernate ตราบใดที่ session ไหนก็ตามยังไม่ยิง `Stop` ซึ่งถูกต้องตาม design แต่ทำให้ hibernate ไม่เกิดขึ้นบ่อยกว่าที่คาดถ้ามี background job ทำงานยาวๆ ระหว่างคืน
- **2026-07-20 บั๊ก task:** task เดิมใช้ `conhost.exe --headless powershell.exe ...` แต่ Task Scheduler exit 0x8007010B (ERROR_DIRECTORY) ทำให้ PowerShell ไม่รันจริง — แก้โดยเปลี่ยน action เป็น `powershell.exe -WindowStyle Hidden ...` ตรงๆ (ทั้ง install.ps1 + re-register task ที่ runtime แล้ว)
