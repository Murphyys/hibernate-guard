# Claude Instructions — hibernate-guard

กฎเฉพาะโปรเจคนี้ (กฎร่วมอยู่ที่ `dev/CLAUDE.md` + `~/.claude/CLAUDE.md`)

## สิ่งที่ต้องรู้ก่อนแก้โค้ด

- **PowerShell 5.1 เท่านั้น** — ห้ามใช้ ternary, `??`, `?.`, pipeline chain `&&`/`||`
- Runtime จริงอยู่ที่ `%LOCALAPPDATA%\HibernateGuard` — แก้โค้ดใน repo แล้วต้องรัน `install.ps1` ซ้ำถึงจะมีผล (ยกเว้น `config.json` ที่ installer จะไม่ทับของเดิม)
- `install.ps1`/`uninstall.ps1` แตะ `~/.claude/settings.json` — แก้ logic ส่วนนี้ต้องระวังไม่ทับ hooks อื่น (มี Obsidian git-push hook อยู่ใน `Stop`)
- การทดสอบ watcher ใช้ `-SimulateIdleSeconds` + `-CountdownOverrideSeconds` (ดู README)
- Scheduled task ชื่อ `HibernateGuard` — `-MultipleInstances IgnoreNew` สำคัญ อย่าเอาออก (กัน instance ซ้อนตอน countdown)

## Install rule — ห้ามติดตั้งผ่าน shell tool ของ AI agent ⚠️

`install.ps1` **ต้องรันจากหน้าต่าง PowerShell จริงของ Ice เท่านั้น** — ห้ามให้ Claude Code (หรือ agent อื่น) รันผ่าน shell tool ของตัวเอง

Shell tool ของ Claude Code รันใน sandbox ที่มี **filesystem overlay**: ไฟล์ที่ copy ลง `%LOCALAPPDATA%\HibernateGuard` จะเห็นแค่ในมุมมองของ tool session เท่านั้น **ไม่ลงดิสก์จริง** ส่วน `Register-ScheduledTask` ไปที่ Task Scheduler service จริง → ได้ task ที่ชี้ไปยังไฟล์ที่ไม่มีอยู่จริง เงียบๆ ไม่มี error

วิธีตรวจว่าติดตั้งจริงหรือไม่ (เช็คจากนอก sandbox เสมอ):

```powershell
Get-ChildItem "$env:LOCALAPPDATA\HibernateGuard"   # ต้องเห็น watcher.ps1 / config.json / busy\
Get-ScheduledTaskInfo -TaskName HibernateGuard     # LastTaskResult ต้องเป็น 0
Get-Content "$env:LOCALAPPDATA\HibernateGuard\watcher.log" -Tail 5   # ต้องมี entry เดินตามเวลาจริง
```

`install.ps1` มี **post-install self-check** (step 6) ที่ยิง task ชั่วคราวไปตรวจว่า Task Scheduler มองเห็น `watcher.ps1` จริงไหม — ถ้าขึ้น FAIL แปลว่ากำลังติดตั้งจาก sandbox ให้ไปรันจาก PowerShell จริง

## Pending / Known issues

- **⏳ รอ Ice arm เอง — ตอนนี้ `dryRun = true` (2026-07-29)** — ติดตั้งลงดิสก์จริงรอบแรกสำเร็จแล้ว แต่ยังไม่เคยผ่านการทดสอบจริงสักครั้ง (ดู root cause ด้านล่าง) จึงตั้ง dry-run ไว้ก่อน ให้ดู `watcher.log` ว่ามี pass เดินจริงตามเวลา + ข้อความ `DRY-RUN: would hibernate now` ขึ้นตอน idle ครบ แล้วค่อยแก้ `dryRun` เป็น `false` ใน `%LOCALAPPDATA%\HibernateGuard\config.json` (แก้ runtime พอ ไม่ต้อง re-install); pause ใช้ `toggle.ps1` หรือสร้าง `paused.flag`
- **⚠️ ต้องยืนยันก่อน arm — busy flag เกิดบนดิสก์จริงหรือยัง:** hooks ใน `~/.claude/settings.json` ลงทะเบียนไว้จริง (ตรวจแล้ว 2026-07-29) แต่ตลอด 20–29 ก.ค. มันชี้ไปยัง `hibernate-hook.ps1` ที่ไม่มีอยู่บนดิสก์จริง → ไม่เคยสร้าง busy flag จริงเลย ตอนนี้ไฟล์อยู่ครบแล้วแต่ **ยังไม่ได้พิสูจน์ว่า hook รันนอก sandbox ได้**. ก่อน flip `dryRun` ให้เช็คว่าเปิด Claude Code session ใหม่แล้วมีไฟล์ `.flag` โผล่ใน `%LOCALAPPDATA%\HibernateGuard\busy\` จริง — ถ้าไม่มี แปลว่า hook เขียนลง overlay เหมือนกัน แล้ว watcher จะ hibernate ทับกลาง session
- Hooks มีผลเฉพาะ Claude Code session ที่เปิดใหม่หลังติดตั้ง — session ที่เปิดค้างก่อนติดตั้งจะไม่สร้าง busy flag
- Background task (`run_in_background`) ไม่ถูกนับเป็น busy — by design (ยอมรับแล้ว)
- **2026-07-20 แก้บั๊ก:** stale-flag cleanup เดิมอยู่ใน `Test-Busy` ซึ่งถูกเรียกก็ต่อเมื่อ idle ผ่าน 30 นาทีแล้ว — ถ้าเครื่อง active ทั้งวัน flag จาก session ที่ crash/ปิดกลางคันจะไม่เคยถูกกวาดเลย แก้โดยแยก `Remove-StaleFlags` ออกมารันทุก pass ไม่ต้องรอ idle (ดู `watcher.ps1`)
- **สังเกตจริง:** เครื่อง Ice มี `claude.exe` process รันพร้อมกันได้เยอะมาก (~14 ตัวตอนตรวจ) จาก MCP/scheduled task ต่างๆ (เช่น todo→Obsidian sync) — busy-check จะบล็อก hibernate ตราบใดที่ session ไหนก็ตามยังไม่ยิง `Stop` ซึ่งถูกต้องตาม design แต่ทำให้ hibernate ไม่เกิดขึ้นบ่อยกว่าที่คาดถ้ามี background job ทำงานยาวๆ ระหว่างคืน
- **✅ 2026-07-29 root cause ที่แท้จริง (แก้แล้ว):** task ไม่เคยรันสำเร็จ**เลยสักครั้ง**ตั้งแต่ติดตั้ง 20 ก.ค. เพราะ `install.ps1` ถูกรันผ่าน shell tool ของ Claude Code → ไฟล์ runtime ลงแค่ใน sandbox overlay **ดิสก์จริงมีแต่โฟลเดอร์เปล่า** (`watcher.log` ไม่เคยมีอยู่จริงด้วยซ้ำ) อาการทุกอย่างอธิบายด้วยข้อนี้ข้อเดียว: `0x8007010B` = ERROR_DIRECTORY (WorkingDirectory ชี้ไปโฟลเดอร์ที่ไม่มี), `0xFFFD0000` = powershell เปิดสคริปต์ `-File` ไม่ได้, entry ใน `watcher.log` มีแค่ 5 นาทีกระจัดกระจาย (= การรันมือทุกครั้ง) ไม่เคยเดินทุก 1 นาที. แก้โดยให้ scheduled task เอง copy ไฟล์จาก repo → runtime (task คือ actor เดียวที่อยู่บนเครื่องจริง) → กฎกันซ้ำอยู่ใน section `Install rule` ด้านบน
- **❌ 2026-07-20 misdiagnosis (ตกไปแล้ว — อย่าเชื่อ):** เคยสรุปว่า "Task Scheduler หยุดรัน process ตั้งแต่ 10:08 / เป็นปัญหา session token / น่าจะแก้ได้ด้วย reboot" — **ผิดทั้งหมด** พิสูจน์แล้วว่า reboot ไป 29 ก.ค. 19:00 ก็ยัง error เดิม และ task อื่นของ user เดียวกัน (OneDrive/Brave/Zoom) รันสำเร็จ 0x0 ตลอด; ส่วนที่อ้างว่า "conhost รันสำเร็จตอน 10:08" คือการรันมือ ไม่ใช่ task
- **ข้อจำกัดของ self-check ใน `install.ps1`:** มันเขียนผล probe ลง `%TEMP%` แล้วอ่านกลับจาก shell ที่ติดตั้ง — ถ้า sandbox รุ่นถัดไป virtualize `%TEMP%` ด้วย มันอาจอ่านค่าจาก overlay แล้วรายงาน PASS ผิดได้ ตอนนี้ครอบเคสที่เจอจริงพอ (overlay เฉพาะ `%LOCALAPPDATA%`) แต่ถ้าจะให้แน่จริงต้องให้ probe task เขียนผลไปที่ path ที่ยืนยันแล้วว่าไม่ถูก virtualize
- **`Microsoft-Windows-TaskScheduler/Operational` log ปิดอยู่** (`IsEnabled: False`) — `wevtutil sl /e:true` รอบก่อนไม่ติด (ต้อง admin) เลยไม่เคยเก็บ event ให้ดูเลย ถ้าจะใช้ debug รอบหน้าต้องเปิดจาก PowerShell ที่ยกสิทธิ์ admin ก่อน
