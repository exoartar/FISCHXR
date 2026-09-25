;==============================================================================
; FISCHXR for AutoHotkey v2.0
;
; Automates the cast, shake and reel loop in the Roblox game Fisch by reading
; pixels on screen. It never touches game memory. Also feeds your aquarium,
; uses totems on a schedule, recharges Sovereign rods, sends Discord alerts
; and rejoins after a disconnect.
;
; Before you start
;   1. In Fisch's settings, set shake mode to Navigation.
;   2. Equip your rod and face the water.
;   3. Press F1 (or Start fishing). F1 again stops. F3 quits.
;
; Rod skins: the first reel with a new rod or skin is learned by watching
; which block of pixels moves with the bar, then kept as a rod look. The
; Rods tab lists them; the Live tab shows what the macro sees.
;
; Scan regions are stored as fractions of the Roblox window, so they adapt to
; any resolution. Library rod colours and the aquarium panel layout come from
; DeepFish v1.0.3 (github.com/yatonomacro/DeepFish).
;
; Settings save to FischMacro.ini next to this file.
;==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SetWorkingDir A_ScriptDir
SendMode "Input"
SetMouseDelay -1
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
CoordMode "Menu", "Screen"
try ProcessSetPriority "AboveNormal"
UsePhysicalPixels()
DllCall("winmm\timeBeginPeriod", "UInt", 1)

APP_NAME := "FISCHXR"
APP_VER := "4.9.2"
UPDATE_URL := "https://raw.githubusercontent.com/exoartar/FISCHXR/main/update.json"
IniPath := A_ScriptDir "\FISCHXR.ini"
; Settings from before the rename come along once.
if (!FileExist(IniPath) && FileExist(A_ScriptDir "\FischMacro.ini"))
    try FileCopy(A_ScriptDir "\FischMacro.ini", IniPath)

;------------------------------------------------------------------------------
; Themes. Black is the default and uses only black, white and greys. Dark
; uses Windows 11 Notepad's greys with a teal accent.
;------------------------------------------------------------------------------
Themes := Map(
    "Black", {strip: "000000", bar: "0C0C0C", seam: "262626", content: "000000",
        field: "161616", fieldHi: "2A2A2A", divider: "303030",
        text: "FFFFFF", dim: "8C8C8C", faint: "4A4A4A",
        accent: "FFFFFF", accentHi: "D9D9D9", ink: "000000",
        wait: "BFBFBF", stop: "FFFFFF", focus: "FFFFFF", ring: 2, dark: true, mono: true},
    "Dark", {strip: "0A0A0A", bar: "1F1F1F", seam: "1C1C1C", content: "272727",
        field: "2F2F2F", fieldHi: "3B3B3B", divider: "323232",
        text: "F2F2F2", dim: "A8A8A8", faint: "707070",
        accent: "45E0C8", accentHi: "7AEEDC", ink: "03201B",
        wait: "F2B24C", stop: "FF7A6E", focus: "FFFFFF", ring: 2, dark: true},
    "Light", {strip: "EBEBEB", bar: "F7F7F7", seam: "DCDCDC", content: "FFFFFF",
        field: "EEEEEE", fieldHi: "E0E0E0", divider: "D4D4D4",
        text: "1A1A1A", dim: "5C5C5C", faint: "999999",
        accent: "00796B", accentHi: "00897B", ink: "FFFFFF",
        wait: "8F5500", stop: "C62828", focus: "000000", ring: 2, dark: false},
    "High contrast", {strip: "000000", bar: "000000", seam: "FFFFFF", content: "000000",
        field: "1C1C1C", fieldHi: "383838", divider: "FFFFFF",
        text: "FFFFFF", dim: "FFFFFF", faint: "C8C8C8",
        accent: "FFFF00", accentHi: "FFFF80", ink: "000000",
        wait: "00FFFF", stop: "FF6A6A", focus: "00FFFF", ring: 3, dark: true}
)
; Okabe-Ito based state colours that stay distinct with red-green colour blindness.
SafeColors := Map(
    "dark", {accent: "56B4E9", accentHi: "8ACCF1", ink: "04121C", wait: "F0E442", stop: "E8883A"},
    "light", {accent: "0072B2", accentHi: "0A82C4", ink: "FFFFFF", wait: "8A6100", stop: "B04A00"}
)

; Layout in design units. Everything is multiplied by the zoom level, and
; AutoHotkey then scales for the screen's DPI.
TAB_H := 0, BAR_H := 0, STATUS_H := 26
; Layout, in design units at 100% zoom. A sidebar of SIDEBAR_W width holds the
; tabs; pages sit to its right in one column of LEFT_W starting at PAGE_X. The
; row controls place themselves relative to PAD, shifted by ColX.
SIDEBAR_W := 52, SIDEBAR_X := 148, NAV_H := 30, PAGE_X := SIDEBAR_W + 16   ; the sidebar shows icons; it opens to SIDEBAR_X on hover
PAD := 24, LEFT_W := 456, DASH_X := PAGE_X, COL2 := PAGE_X
ROW_Y0 := 80, ROW_H := 34
MIN_W := 540, MIN_H := 400
BasicTabs := ["Home", "Fishing", "Totems", "Aquarium", "Sovereign", "Alerts", "Reconnect", "Settings"]
AdvTabs := ["Rods", "Live", "Reel", "Timing", "More"]
TabNames := ["Home", "Fishing", "Totems", "Aquarium", "Sovereign", "Alerts", "Reconnect", "Settings", "Rods", "Live", "Reel", "Timing", "More"]
WidePages := ""
ZoomSteps := [80, 90, 100, 110, 125, 150, 175, 200]
; Saved rod looks carry this number; looks with a lower one are relearned
; once (2: artwork printed on the bar is learned as bar, not as the fish).
LOOK_FORMAT := 2
; Where Fisch's own buttons sit, as offsets from the window's centre in
; window heights (across) and fractions of the height from the top (down).
; Fisch's interface scales with the window height, so these hold at any
; size. Measured on a 3838x2158 screen.
UiSpots := Map(
    "aquariums",  [0.0732, 0.0222],     ; the Aquariums tab at the top
    "enchantRod", [-0.0823, 0.6938],    ; inventory: Enchant Rod
    "search",     [0.0776, 0.7268],     ; inventory: the search box
    "firstItem",  [-0.1910, 0.7705],    ; inventory: the first slot
    "confirm",    [0.0524, 0.8397])     ; the "Enchant your Rod?" Confirm

; Totems the schedule can hold (name, night-only), and the Discord alert
; kinds with the setting that switches each on and its message title.
TotemPresets := [["Aurora", 1], ["Sundial", 0], ["Clearcast", 0], ["Tempest", 0], ["Windset", 0], ["Smokescreen", 0]
    , ["Eclipse", 0], ["Meteor", 0], ["Blizzard", 0], ["Avalanche", 0], ["Starfall", 0], ["Blue Moon", 1]
    , ["Zeus Storm", 0], ["Poseidon's Wrath", 0], ["Rainbow", 0], ["Mutation", 0], ["Shiny", 0], ["Sparkling", 0]]
TOTEM_MAX := 6
HookKinds := Map("start", "HookStart", "stop", "HookStart", "error", "HookErrors", "disconnect", "HookDisconnect"
    , "reconnect", "HookDisconnect", "aquarium", "HookJobs", "totem", "HookJobs", "sovereign", "HookJobs")
HookTitles := Map("start", "Fishing started", "stop", "Fishing stopped", "error", "Needs attention", "disconnect", "Disconnected"
    , "reconnect", "Back in the game", "aquarium", "Aquarium", "totem", "Totem", "sovereign", "Sovereign recharge"
    , "summary", "Session summary", "test", "Test alert")

;------------------------------------------------------------------------------
; Settings. Regions are fractions of the Roblox client area.
;------------------------------------------------------------------------------
Defaults := Map(
    "ToggleKey", "F1", "ExitKey", "F3", "RodKey", "1",
    "CastHold", 1000, "BobberWait", 1000, "BiteTimeout", 30, "CatchDelay", 1000, "RodReequip", 0,
    "ShakeMode", "Navigation", "ShakeInterval", 25, "UseNavKey", 0, "NavKey", "\", "ShakeTol", 3,
    "ControlStyle", "physics", "Latency", 0, "Braking", 100, "Predict", 70,
    "EdgeMargin", 8, "ScanDelay", 4, "LearnedLag", 0, "FishLead", 70,
    "ReelX1", 0.30157, "ReelY1", 0.84239, "ReelX2", 0.69847, "ReelY2", 0.86866,
    "ShakeX1", 0.22, "ShakeY1", 0.10, "ShakeX2", 0.78, "ShakeY2", 0.75,
    "AqAuto", 0, "AqEvery", 63, "AqMaxUses", 12, "AqMaxBuys", 8, "AqStepDelay", 320,
    "AqOpenWait", 1500, "AqScrollSteps", 14,
    "Theme", "Black", "Zoom", 100, "ColorSafe", 0, "ReduceMotion", 0, "Speak", 0, "Sounds", 0,
    "ShowSplash", 1, "ShowHome", 1, "OnTop", 1, "ShowAreas", 0, "LastTab", "Fishing",
    "WinX", "", "WinY", "", "WinW", 540, "WinH", 416,
    "TotemAuto", 0, "TotemWait", 2500, "TotemSundial", 1, "NightLevel", 70,
    "SovAuto", 0, "SovEvery", 20, "SovCount", 1, "SovInvKey", "``", "SovStep", 350, "SovOpenWait", 900,
    "HookUrl", "", "HookUser", "", "HookStart", 1, "HookErrors", 1, "HookDisconnect", 1, "HookJobs", 0,
    "HookSummary", 60, "HookShots", 1,
    "AutoReconnect", 0, "RejoinLink", "roblox://experiences/start?placeId=16732694052", "RejoinWait", 40,
    "AuthMode", "", "AuthTok", "", "AuthExp", 0, "AuthName", "", "AuthId", "", "RodManual", "",
    "RejoinMax", 4, "RejoinResume", 1, "ReelSnaps", 1,
    "MiniHud", 1, "UpdateUrl", UPDATE_URL, "AutoUpdate", 1, "LastVersion", ""
)
TextKeys := "|RodManual|AuthMode|AuthTok|AuthName|AuthId|ToggleKey|ExitKey|RodKey|ShakeMode|NavKey|ControlStyle|Theme|LastTab|WinX|WinY|SovInvKey|HookUrl|HookUser|RejoinLink|UpdateUrl|LastVersion|"
BoolKeys := ["RodReequip", "UseNavKey", "AqAuto", "ColorSafe", "ReduceMotion", "Speak", "Sounds", "ShowSplash", "ShowHome", "OnTop", "ShowAreas"
    , "TotemAuto", "TotemSundial", "SovAuto", "HookStart", "HookErrors", "HookDisconnect", "HookJobs", "HookShots", "AutoReconnect", "RejoinResume", "ReelSnaps", "MiniHud", "AutoUpdate"]

NumSpec := Map(
    "CastHold",      {label: "Cast hold",        unit: "ms",  min: 100, max: 3000, step: 50,  help: "How long the mouse is held to cast."},
    "BobberWait",    {label: "Wait after cast",  unit: "ms",  min: 0,   max: 5000, step: 100, help: "Pause after the cast so the bobber can land before shaking starts."},
    "BiteTimeout",   {label: "Recast after",     unit: "s",   min: 5,   max: 120,  step: 5,   help: "If no reel bar shows up in this time, the macro casts again."},
    "CatchDelay",    {label: "Pause after reel", unit: "ms",  min: 0,   max: 5000, step: 100, help: "Time to wait after a reel ends while the catch popup clears."},
    "ShakeInterval", {label: "Shake every",      unit: "ms",  min: 10,  max: 500,  step: 5,   help: "Time between Enter presses, or clicks in Click mode. Lower shakes faster."},
    "ShakeTol",      {label: "Button match",     unit: "",    min: 0,   max: 60,   step: 1,   help: "Click mode only. How far a pixel may be from pure white and still count as the shake button."},
    "Latency",       {label: "Latency",          unit: "ms",  min: 0,   max: 200,  step: 5,   help: "Auto measures the delay between the screen and Roblox reacting while you reel. Set a number to use your own; raise it if the bar keeps overshooting."},
    "Braking",       {label: "Braking margin",   unit: "%",   min: 50,  max: 250,  step: 5,   help: "Scales how early the bar brakes. Above 100 brakes sooner, below 100 later."},
    "Predict",       {label: "Look-ahead",       unit: "ms",  min: 0,   max: 400,  step: 5,   help: "Simple control style only. How far ahead the bar position is predicted."},
    "EdgeMargin",    {label: "Edge zone",        unit: "%",   min: 0,   max: 30,   step: 1,   help: "When the fish is this close to either end, the bar is pinned against that wall."},
    "ScanDelay",     {label: "Scan delay",       unit: "ms",  min: 1,   max: 50,   step: 1,   help: "Pause between reel scans. Lower reacts faster and uses more CPU."},
    "AqEvery",       {label: "Feed every",       unit: "min", min: 5,   max: 240,  step: 1,   help: "How often the aquarium routine runs between catches."},
    "AqMaxUses",     {label: "Max food per visit", unit: "",  min: 1,   max: 40,   step: 1,   help: "Upper limit on food cards used plus bought in one visit."},
    "AqMaxBuys",     {label: "Max buys per visit", unit: "",  min: 0,   max: 20,   step: 1,   help: "How many food cards may be bought per visit. Zero never buys."},
    "AqStepDelay",   {label: "Click spacing",    unit: "ms",  min: 100, max: 2000, step: 20,  help: "Pause after each click in the aquarium panel."},
    "AqOpenWait",    {label: "Panel open wait",  unit: "ms",  min: 300, max: 6000, step: 100, help: "Extra time allowed for the aquarium panel to open or close."},
    "Zoom",          {label: "Zoom",             unit: "%",   min: 80,  max: 200,  step: 10,  help: "Scales the whole window. Ctrl+plus, Ctrl+minus and Ctrl+0 also work."},
    "TotemWait",     {label: "Wait after using", unit: "ms",  min: 500, max: 10000, step: 100, help: "Time allowed for a totem's animation before the rod goes back in hand."},
    "NightLevel",    {label: "Night below",      unit: "",    min: 5,   max: 250,  step: 5,   help: "Sky brightness under which it counts as night, for night-only totems. The current level shows below."},
    "SovEvery",      {label: "Recharge every",   unit: "reels", min: 1, max: 500,  step: 1,   help: "How many reels between Sovereign recharges. Only rods marked Sovereign are recharged."},
    "SovCount",      {label: "Relics per recharge", unit: "", min: 1,   max: 20,   step: 1,   help: "How many times Enchant Rod and Confirm are pressed per recharge. Each uses one relic."},
    "SovStep",       {label: "Click spacing",    unit: "ms",  min: 100, max: 3000, step: 50,  help: "Pause between the recharge clicks."},
    "SovOpenWait",   {label: "Inventory open wait", unit: "ms", min: 200, max: 5000, step: 100, help: "Time allowed for the inventory to open before the relic is picked."},
    "HookSummary",   {label: "Summary every",    unit: "min", min: 0,   max: 240,  step: 5,   help: "Sends a catch summary to Discord on this schedule while fishing. Off sends none."},
    "RejoinWait",    {label: "Load time",        unit: "s",   min: 10,  max: 180,  step: 5,   help: "How long to let Fisch load after Roblox reopens, before fishing resumes."},
    "RejoinMax",     {label: "Rejoins per hour", unit: "",    min: 1,   max: 20,   step: 1,   help: "After this many rejoins in an hour the macro stops, since something is wrong."}
)

;------------------------------------------------------------------------------
; Rod library. Each rod paints the reel bar and fish marker differently.
; In Auto mode every signature is tried when the reel starts, and an unknown
; rod has its colours learned by contrast against the track.
;------------------------------------------------------------------------------
; Built-in reel styles. The rod name read from the hotbar picks one; if it
; can't be read, the style that fits the reel is used. Nothing is learned or
; saved about rods. greenBar: green inside the bar counts as bar, and the
; fish is aimed at that green zone (Verdant Oath).
RodLib := [
    {id: "standard",    name: "Standard",               fish: ["434B5B"], ft: 5,  bar: ["F1F1F1", "848587"], bt: 6},
    {id: "verdant",     name: "Verdant Oath",           kind: "wood", fish: ["434B5B"], ft: 12, bar: ["67512C", "65502D"], bt: 5, greenBar: true},
    {id: "halibut",     name: "Halibut Harpoon",        fish: ["0D0B0B"], ft: 5,  bar: ["5D52A8"], bt: 5},
    {id: "remembrance", name: "Remembrance",            fish: ["FFFFFF"], ft: 10, bar: ["B5B5B5"], bt: 10},
    {id: "departed",    name: "Remembrance (Departed)", fish: ["FFFFFF"], ft: 10, bar: ["474747"], bt: 8},
    {id: "migu",        name: "Migu Rod",               fish: ["F9D9D4", "FAD6CE", "F9D4C7", "F9D2C4", "F8D0B7"], ft: 10, bar: ["E9B681", "E0A66F", "D1935B"], bt: 8},
    {id: "pinion",      name: "Pinion's Aria",          kind: "caps", notes: true, fish: [], ft: 8, bar: [], bt: 8},
    {id: "apollo",      name: "Apollo's Sunshot",       kind: "sun", fish: [], ft: 8, bar: [], bt: 8},
    {id: "requiem",     name: "Requiem",                kind: "teal", minSwitch: 200, fish: [], ft: 8, bar: [], bt: 8},
    {id: "pinion_plain", alias: "pinion", name: "Pinion's Aria", kind: "lite", notes: true, fish: [], ft: 8, bar: [], bt: 8},
    {id: "noiseform",   name: "Noiseform",              kind: "box", fish: ["0C4125", "003820", "0D3A27"], ft: 8
        , bar: ["33A95F", "2C894D", "2AB778", "5CBD8C", "74C198", "60BC8E", "19B572", "010101"], bt: 10}
]

;------------------------------------------------------------------------------
; Runtime state
;------------------------------------------------------------------------------
Cfg := Map(), Dirty := Map(), RodMem := Map()
Pal := {}, Zoom := 1.0, HasIconFont := false, IconFace := ""
MainGui := 0, UiReady := false
UI := {}, Clickables := Map(), Pages := Map(), FocusGlobal := [], DescOf := Map()
Steppers := Map(), Toggles := Map(), KeyBtns := Map(), SegCtls := Map(), Swatches := Map(), Choices := Map(), SwitchPos := Map()
Menus := Map(), Brushes := Map()
Stats := {casts: 0, reels: 0, misses: 0, start: 0}
Phase := {kind: "idle", title: "Ready", detail: ""}
Repeat := {key: "", dir: 0, hwnd: 0, n: 0}
Running := false, LoopActive := false, Calibrating := false, Capturing := false, MenuOpen := false
RobloxHwnd := 0, RobloxInfo := {found: false, w: 0, h: 0}
Hover := 0, CalFlag := "", FreezeHwnd := 0, NoSave := false, ResetArmed := false
OutReel := 0, OutShake := 0, OutAq := 0, CurTab := "Home"
CurRod := 0, SelRod := 0, RodProfiles := [], ProfSeq := 0, VisionLog := []
LiveBand := 0, LiveGeo := 0, LiveD := 0, LiveP := 0, LiveEp := -1, LiveT := 0, LiveHbm := 0, LiveRate := 0
UpdAllowLocal := false, UpdLast := ""
ShapeWhy := "", UnmatchedAt := 0, CalmZoneOn := true
; Discord sign-in. The app's Client ID is public by design (no secret is used).
DISCORD_CLIENT_ID := "1552771662787903568", DISCORD_PORT := 53682, DISCORD_INVITE := "https://discord.gg/ERkjTTYG4B"
GUEST_TABS := ["Aquarium", "Sovereign", "Alerts", "Reconnect"]      ; (totems are open to guests)
AuthState := {mode: "", id: "", name: ""}
; (a test harness may set AuthTest before loading the macro)
AuthTest := IsSet(AuthTest) ? AuthTest : {noPrompt: false, noBrowser: false, me: 0, state: "", opened: "", mode: ""}
if AuthTest.noPrompt
    AuthState.mode := AuthTest.mode != "" ? AuthTest.mode : "discord"
SessionLooks := Map(), CurRodName := "", CurRodLib := "", RodReadBusy := false, RodReadAt := 0, RodReadLast := "", OcrHook := 0
LivePreview := false, PreviewBand := 0, PreviewGeo := 0, EditCtls := Map(), ColX := 0, RowBase := 0
Totems := [], SovReels := 0, SovLast := ""
HookQueue := [], HookReq := 0, HookBusy := 0, HookLast := "", HookAllowLocal := false, HookItem := 0
ReconnectWhy := "", ReconnectTimes := [], RejoinHook := 0, LogDirOverride := "", LogConfirmMs := 12000
LogFile := "", LogPos := -1, LogPending := 0, LogJoinT := 0, LogTeleT := 0, LogLastLine := ""
AqNext := 0, AqManual := false, AqAbort := false, AqLast := ""
Events := [], FocusIdx := 0, FocusOn := false, Maxed := false, NormalRect := 0
Voice := 0, GaugeState := {l: 0.36, r: 0.64, f: 0.5, live: false}
RodInfoText := "Waiting for the first reel"

;------------------------------------------------------------------------------
; Startup: settings, loading screen, then the window with the start menu
;------------------------------------------------------------------------------
; An existing settings file means this is an upgrade (for What's new), and
; one saved before the sidebar layout gets the new, smaller window size.
WasExistingIni := FileExist(IniPath) != ""
OldLayout := WasExistingIni && IniRead(IniPath, "Settings", "UiVersion", 0) < 3
LoadSettings()
if OldLayout {
    Cfg["WinW"] := Defaults["WinW"], Cfg["WinH"] := Defaults["WinH"]
    try IniWrite(Cfg["WinW"], IniPath, "Settings", "WinW"), IniWrite(Cfg["WinH"], IniPath, "Settings", "WinH")
}
try IniWrite(3, IniPath, "Settings", "UiVersion")
if (Trim(Cfg["UpdateUrl"]) = "")             ; an empty saved link means the built-in one
    Cfg["UpdateUrl"] := UPDATE_URL
LoadRodMemory()
LoadTotems()
ResolveTheme()
DetectIconFont()
OnMessage(0x0014, WM_ERASEBKGND)
OnMessage(0x0201, WM_LBUTTONDOWN)
OnMessage(0x0203, WM_LBUTTONDOWN)  ; fast second clicks arrive as double-clicks
OnMessage(0x0200, WM_MOUSEMOVE)
OnMessage(0x020A, WM_MOUSEWHEEL)
OnMessage(0x0020, WM_SETCURSOR)
OnMessage(0x0100, WM_KEYDOWN)       ; keys for this window arrive as messages: no keyboard hook
OnMessage(0x0104, WM_KEYDOWN)       ; Alt combinations and F10 arrive as system keys
OnMessage(0x0105, WM_SYSKEYUP)
OnExit(Cleanup)
Boot()
if !BindHotkeys() {
    Cfg["ToggleKey"] := Defaults["ToggleKey"], Cfg["ExitKey"] := Defaults["ExitKey"]
    BindHotkeys()
    UpdateStartControls()
}
SetupTray()
if !Login.g                             ; (with the sign-in screen up, What's new waits for it)
    SetTimer(WhatsNewCheck, -1500)
if (Cfg["AutoUpdate"] && Cfg["UpdateUrl"] != "")
    SetTimer(() => CheckForUpdate(true), -4000)
SetTimer(RefreshRobloxInfo, 2000)
if Cfg["ShowAreas"]
    SetTimer(UpdateOverlay, 500)

Boot() {
    global CurRodName, CurRodLib
    if (Cfg["RodManual"] != "")                 ; a rod typed on the Rods page stays in use
        CurRodName := Cfg["RodManual"], CurRodLib := RodLibFor(Cfg["RodManual"])
    show := Cfg["ShowSplash"]
    if show
        Splash.Show()
    steps := [
        ["Loading settings", 16, () => 0],
        ["Loading settings and totems", 34, () => 0],
        ["Looking for Roblox", 56, () => RefreshRobloxInfo()],
        ["Preparing detection", 74, () => 0],
        ["Building the window", 94, () => BuildGui()]
    ]
    for s in steps {
        if show
            Splash.Step(s[1], s[2])
        s[3].Call()
        if (show && !Cfg["ReduceMotion"])
            Sleep 110
    }
    if show {
        Splash.Step("Ready", 100)
        if !Cfg["ReduceMotion"]
            Sleep 160
    }
    ; the program opens signed in (a remembered Discord sign-in), or on the
    ; sign-in screen, which is all there is until a choice is made
    if show
        Splash.Step("Checking your sign-in", 98)
    tab := Cfg["ShowHome"] ? "Home" : Cfg["LastTab"]
    if AuthGate()
        ShowMain(tab)
    else
        Login.Show(tab)
    if show
        Splash.Close()
    LogEvent("Opened")
}

; Loading screen: the logo on black with real startup steps and a progress
; line. It is a brand screen, so it stays black and white in every theme.
; The fish bobs gently while it loads unless motion is reduced.
class Splash {
    static g := 0, fill := 0, rest := 0, label := 0, pct := 0, x0 := 0, tw := 0, logo := 0, hbm := 0, ly := 0, t0 := 0
    static Show() {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow", APP_NAME)
        g.BackColor := "000000"
        g.MarginX := 0, g.MarginY := 0
        W := ZS(480), L := ZS(176)
        this.ly := ZS(24)
        if (src := LogoImage("splash")) && (this.hbm := GpScaled(src, L, L, 0))
            this.logo := g.Add("Picture", Format("x{} y{} w{} h{}", (W - L) // 2, this.ly, L, L), "HBITMAP:*" this.hbm)
        SetFontFor(g, "norm s" FZ(20) " cFFFFFF q4", "display")
        g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(212), W), "F I S C H X R")
        SetFontFor(g, "norm s" FZ(9) " c8C8C8C q4", "body")
        g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(248), W), "v" APP_VER)
        this.x0 := ZS(90), this.tw := ZS(300)
        this.fill := g.Add("Text", Format("x{} y{} w1 h{} BackgroundFFFFFF", this.x0, ZS(282), ZS(2)))
        this.rest := g.Add("Text", Format("x{} y{} w{} h{} Background262626", this.x0 + 1, ZS(282), this.tw - 1, ZS(2)))
        SetFontFor(g, "norm s" FZ(9) " cBFBFBF q4", "body")
        this.label := g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(292), W), "Starting")
        SetFontFor(g, "norm s" FZ(8) " c5A5A5A q4", "body")
        g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(326), W)
            , KeyName(Cfg["ToggleKey"]) " starts and stops   ·   " KeyName(Cfg["ExitKey"]) " quits")
        g.Show(Format("w{} h{}", W, ZS(354)))
        StyleWindow(g.Hwnd)
        try ApplyAppIcon(g.Hwnd)
        this.g := g, this.pct := 0, this.t0 := A_TickCount
    }
    static Step(text, pct) {
        if !this.g
            return
        this.label.Text := text
        frames := Cfg["ReduceMotion"] ? 1 : 6
        from := this.pct
        Loop frames {
            p := from + (pct - from) * A_Index / frames
            fw := Max(1, Round(this.tw * p / 100))
            this.fill.Move(, , fw)
            this.rest.Move(this.x0 + fw, , Max(0, this.tw - fw))
            if (frames > 1) {
                if this.logo
                    this.logo.Move(, this.ly + Round(ZS(4) * Sin((A_TickCount - this.t0) / 260)))
                Sleep 16
            }
        }
        this.pct := pct
    }
    static Close() {
        if this.g {
            this.g.Destroy()
            this.g := 0
        }
        if this.hbm
            DllCall("DeleteObject", "Ptr", this.hbm), this.hbm := 0
        this.logo := 0
    }
}

;------------------------------------------------------------------------------
; Settings storage
;------------------------------------------------------------------------------
LoadSettings() {
    global Zoom
    for k, def in Defaults {
        v := IniRead(IniPath, "Settings", k, def)
        if !InStr(TextKeys, "|" k "|")
            v := IsNumber(v) ? v + 0 : def
        Cfg[k] := v
    }
    for k, sp in NumSpec
        Cfg[k] := Clamp(Round(Cfg[k]), sp.min, sp.max)
    for k in BoolKeys
        Cfg[k] := Cfg[k] ? 1 : 0
    if (Cfg["ShakeMode"] != "Navigation" && Cfg["ShakeMode"] != "Click")
        Cfg["ShakeMode"] := "Navigation"
    if (Cfg["ControlStyle"] != "physics" && Cfg["ControlStyle"] != "simple")
        Cfg["ControlStyle"] := "physics"
    if !Themes.Has(Cfg["Theme"])
        Cfg["Theme"] := "Black"
    old := Map("Cast", "Fishing", "Shake", "Fishing", "Accessibility", "Settings", "Setup", "Settings")
    if old.Has(Cfg["LastTab"])
        Cfg["LastTab"] := old[Cfg["LastTab"]]
    ok := false
    for t in TabNames
        ok := ok || (t = Cfg["LastTab"])
    if !ok
        Cfg["LastTab"] := "Fishing"

    for k in ["ToggleKey", "ExitKey", "RodKey", "NavKey"]
        if (Trim(Cfg[k]) = "")
            Cfg[k] := Defaults[k]
    for name in ["Reel", "Shake"] {
        good := true
        for k in ["X1", "Y1", "X2", "Y2"]
            if (Cfg[name k] < 0 || Cfg[name k] > 1)
                good := false
        if (!good || Cfg[name "X2"] - Cfg[name "X1"] < 0.02 || Cfg[name "Y2"] - Cfg[name "Y1"] < 0.002)
            for k in ["X1", "Y1", "X2", "Y2"]
                Cfg[name k] := Defaults[name k]
    }
    Cfg["WinW"] := Max(MIN_W, Cfg["WinW"]), Cfg["WinH"] := Max(MIN_H, Cfg["WinH"])
    Zoom := Cfg["Zoom"] / 100
}

Save(k) {
    Dirty[k] := true
    SetTimer(FlushSaves, -400)
}

FlushSaves() {
    if NoSave
        return
    for k in Dirty {
        v := Cfg[k]
        if RegExMatch(k, "^(Reel|Shake)[XY][12]$")
            v := Format("{:.5f}", v)
        try IniWrite(v, IniPath, "Settings", k)
    }
    Dirty.Clear()
}

; Learned bar physics per rod, keyed by rod and bar width: "standard@31=3.10,2.85,7"
LoadRodMemory() {
    try section := IniRead(IniPath, "Rods")
    catch
        return
    Loop Parse, section, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^([\w-]+@\d+)=([\d.]+),([\d.]+),(\d+)$", &m)
            continue
        RodMem[m[1]] := {aH: m[2] + 0, aR: m[3] + 0, n: m[4] + 0}
    }
}

RememberRod(key, aH, aR) {
    n := RodMem.Has(key) ? RodMem[key].n + 1 : 1
    RodMem[key] := {aH: aH, aR: aR, n: n}
    if !NoSave
        try IniWrite(Format("{:.3f},{:.3f},{}", aH, aR, n), IniPath, "Rods", key)
}

ResolveTheme() {
    global Pal
    base := Themes[Cfg["Theme"]]
    Pal := {}
    for k, v in base.OwnProps()
        Pal.%k% := v
    if (Cfg["ColorSafe"] && !base.HasOwnProp("mono") && Cfg["Theme"] != "High contrast") {
        for k, v in SafeColors[base.dark ? "dark" : "light"].OwnProps()
            Pal.%k% := v
    }
}

; Library rods (their own reel colours), by id.
RodById(id) {
    for p in RodLib
        if (p.id = id)
            return p
    return {id: id, name: "Rod"}
}


;==============================================================================
; Macro control
;==============================================================================
ToggleMacro() {
    global AqAbort
    if (AuthState.mode = "")                    ; the sign-in screen is up: nothing runs until a choice
        return
    if (Calibrating || Capturing)
        return
    if AqManual {
        AqAbort := true
        return
    }
    if Running
        StopMacro()
    else if !LoopActive
        StartMacro()
}

StartMacro() {
    global Running, RobloxHwnd, SovReels, ReconnectWhy, LogFile
    UsePhysicalPixels()
    hwnd := FindRoblox()
    if !hwnd {
        SetPhase("error", "Roblox isn't open", "Open Fisch, then press " KeyName(Cfg["ToggleKey"]) ".")
        Cue("error")
        return
    }
    if PanelCoversReel(hwnd) {
        SetPhase("error", "Window is in the way", "Move this window off the reel bar, then start again.")
        Cue("error")
        return
    }
    RobloxHwnd := hwnd
    Running := true
    Stats.casts := 0, Stats.reels := 0, Stats.misses := 0, Stats.start := A_TickCount
    SovReels := 0, ReconnectWhy := "", LogFile := ""
    ScheduleTotems()
    UpdateStats()
    SetTimer(TickClock, 1000)
    if Cfg["AutoReconnect"]
        SetTimer(WatchConnection, 3000)
    if Cfg["HookSummary"]
        SetTimer(SummaryTick, Cfg["HookSummary"] * 60000)
    UpdateStartControls()
    HudEnter()
    SetTimer(ReadRodName, -400)            ; which rod is in hand
    LogEvent("Started fishing")
    Alert("start", "Fishing started" (IsObject(CurRod) ? " with " CurRod.name : "") ".")
    Cue("start")
    try WinActivate("ahk_id " hwnd)
    SetTimer(MacroLoop, -1)
}

StopMacro(msg := "") {
    global Running
    was := Running
    Running := false
    ReleaseMouse()
    SetTimer(TickClock, 0)
    SetTimer(WatchConnection, 0)
    SetTimer(SummaryTick, 0)
    UpdateStartControls()
    HudLeave()
    mins := Round((A_TickCount - Stats.start) / 60000)
    if (msg != "") {
        SetPhase("error", "Stopped", msg)
        Cue("error")
        LogEvent("Stopped: " msg)
        if was
            Alert("error", "Fishing stopped: " msg, true)
    } else {
        if was
            Alert("stop", Format("Fishing stopped after {} min: {} casts, {} reels.", mins, Stats.casts, Stats.reels))
        SetPhase("idle", "Ready", IdleHint())
        if was
            LogEvent("Stopped")
    }
    SetGauge(0.36, 0.64, 0.5, false)
}

MacroLoop() {
    global LoopActive, CurRod, SovReels, LiveBand, LiveGeo
    LoopActive := true
    UsePhysicalPixels()
    misses := 0, b := 0, geoKey := ""
    try {
        while Running {
            if ReconnectDue() {
                if !Reconnect()
                    break
                continue
            }
            if !WinExist("ahk_id " RobloxHwnd) {
                if Cfg["AutoReconnect"] {
                    FlagDisconnect("The Roblox window closed")
                    continue
                }
                StopMacro("Roblox closed. Reopen Fisch and press " KeyName(Cfg["ToggleKey"]) ".")
                break
            }
            if !WaitForFocus() {
                if ReconnectDue()
                    continue
                break
            }
            cr := ClientRect(RobloxHwnd)
            if !cr {
                SetPhase("pause", "Paused", "Restore the Roblox window to continue.")
                Sleep 300
                continue
            }
            ; Jobs between catches: aquarium, totems, Sovereign recharge.
            if RunDueJobs()
                continue
            a := AreaRect("Reel", cr), geo := VisionGeo(a)
            k := geo.x "," geo.y "," geo.w "," geo.h
            if (k != geoKey)
                b := BandGrab(geo.w, geo.h), geoKey := k
            LiveBand := b, LiveGeo := geo

            if (Cfg["RodReequip"] && misses >= 3) {
                SetPhase("cast", "Re-equipping rod", "Three casts in a row got no bite.")
                misses := 0
                if !ReequipRod() {
                    if ReconnectDue()
                        continue
                    break
                }
            }
            SetPhase("cast", "Casting", "Holding the cast for " Cfg["CastHold"] " ms.")
            if !Cast() {
                if ReconnectDue()
                    continue
                break
            }
            Stats.casts++
            UpdateStats()
            if !Nap(Cfg["BobberWait"])
                break

            ; Remember the reel row before any bite, so the reel UI can be told
            ; apart from scenery that happens to share its colours.
            VisionGrab(b, geo)
            base := ColsCopy(b)
            SetPhase("wait", "Waiting for a bite")
            found := ShakeUntilReel(b, geo, base)
            if !IsObject(found) {
                if (found = "stop") {
                    if ReconnectDue()
                        continue
                    break
                }
                misses++
                Stats.misses++
                LogEvent("No bite, recasting")
                continue
            }
            misses := 0
            CurRod := found.prof
            SetPhase("reel", "Reeling", "Rod: " found.prof.name)
            MouseToCenter()
            res := Reel(b, geo, base, found)
            ; A reel that ended early (lost tracking) while its UI is still up
            ; is resumed rather than cast over.
            resumes := 0
            while (Running && !res.phantom && resumes < 3 && ReelStillUp(b, geo, found.prof)) {
                resumes++
                LogVision("Reel still up after tracking dropped; resuming")
                res := Reel(b, geo, base, {prof: found.prof, d: 0})
            }
            if !Running
                break
            if ReconnectDue()          ; the game dropped mid-reel: don't count it
                continue
            Stats.reels++
            SovReels++
            UpdateStats()
            SetGauge(0.36, 0.64, 0.5, false)
            if res.phantom
                LogEvent("Reel ended early: the bar stopped answering the mouse")
            else
                LogEvent(Format("Reel done in {:.1f} s, fish centered {}", res.dur / 1000, res.centeredTxt))
            Cue("catch")
            SetPhase("cast", "Reel finished", "Casting again shortly.")
            if !Nap(Cfg["CatchDelay"])
                break
        }
    } catch as err {
        StopMacro("Something went wrong: " err.Message)
    } finally {
        ReleaseMouse()
        LoopActive := false
    }
}

; Runs whichever between-catch job is due. True when one ran.
RunDueJobs() {
    if (Cfg["AqAuto"] && A_TickCount >= AqNext) {
        RunAquarium(false)
        return true
    }
    if TotemDue() {
        RunTotems()
        return true
    }
    if SovereignDue() {
        RunSovereign()
        return true
    }
    return false
}

Cast() {
    if !WaitForFocus()
        return false
    MouseToCenter()
    Sleep 30
    Click("Down")
    ok := Nap(Cfg["CastHold"])
    Click("Up")
    return ok
}

ReequipRod() {
    key := "{" Cfg["RodKey"] "}"
    Send key
    if !Nap(500)
        return false
    Send key
    return Nap(800)
}

; Presses Enter (Navigation mode) or clicks the shake button (Click mode)
; until a reel UI shows up or the bite timer runs out.
; Shakes until the reel shows up, then works out which look it is: a known
; look, a rod with its own reel colours, or (once the track outline is
; visible) a new look learned on the spot.
ShakeUntilReel(b, geo, base) {
    deadline := A_TickCount + Cfg["BiteTimeout"] * 1000
    nav := (Cfg["ShakeMode"] = "Navigation")
    navOn := false
    if (nav && Cfg["UseNavKey"]) {
        Send "{" Cfg["NavKey"] "}"
        navOn := true
    }
    hits := 0, lastShake := 0, lastNote := 0, lastLearn := 0, why := "", quiet := QuietRod()
    ; the rod's name decides its reel style; while it's unknown, read it again
    if (CurRodName = "" && A_TickCount - RodReadAt > 20000)
        SetTimer(ReadRodName, -10)
    while Running {
        if (!WaitForFocus() || ReconnectDue())
            return "stop"
        VisionGrab(b, geo)
        r := 0
        changed := RowDiff(b, base) > 0.25
        if changed {
            r := MatchPrecoded(b, geo)
            if (!r && A_TickCount - lastLearn > 4000) {
                lastLearn := A_TickCount
                LogVision("No built-in reel style fits this reel" (CurRodName != "" ? " (" CurRodName ")" : "")
                    . (ShapeWhy != "" ? ": " ShapeWhy : ""))
                SaveUnmatched(b)
            }
        }
        if r {
            if (++hits >= 2) {
                if navOn
                    Send "{" Cfg["NavKey"] "}"
                return r
            }
        } else {
            hits := 0
        }
        now := A_TickCount
        if (now >= deadline) {
            if navOn
                Send "{" Cfg["NavKey"] "}"
            return "timeout"
        }
        ; No shaking once a reel is showing. For rods that lose the fish to
        ; fast inputs (Requiem), none as soon as the reel area changes, even
        ; before the reel is recognized.
        if (now - lastShake >= Cfg["ShakeInterval"] && !r && !(quiet && changed)) {
            lastShake := now
            if nav
                Send "{Enter}"
            else
                ClickShake()
        }
        if (now - lastNote >= 500) {
            lastNote := now
            SetDetail("Recasting in " Ceil((deadline - now) / 1000) " s if nothing bites.")
        }
        Sleep 3
    }
    return "stop"
}

; Checks one stretch of constant input: the bar must accelerate the way the
; mouse says. Four long stretches in a row failing means the "bar" is
; scenery that happens to share the look's colours.
SegmentAnswers(ts, xs, held, est, okList) {
    n := ts.Length
    if (n < 8 || ts[n] - ts[1] < 90)
        return true
    acc := QuadAccel(ts, xs)
    if (acc = "")
        return true
    ok := held ? acc > 0.25 * est.aH : acc < -0.25 * est.aR
    okList.Push(ok)
    if (okList.Length > 4)
        okList.RemoveAt(1)
    if (okList.Length < 4)
        return true
    for v in okList
        if v
            return true
    return false
}

; Fraction of columns whose colour changed from the reference row.
RowDiff(b, base) {
    n := 0, cols := b.cols
    Loop b.w {
        o := (A_Index - 1) * 4
        if (ColDist(NumGet(cols, o, "UInt"), NumGet(base, o, "UInt")) > 28)
            n++
    }
    return n / b.w
}

ColsCopy(b) {
    c := Buffer(b.w * 4)
    DllCall("RtlMoveMemory", "Ptr", c, "Ptr", b.cols, "UPtr", b.w * 4)
    return c
}

; After a reel ends, is it actually still up? Two of three looks must show
; it: the track outline where this look's outline sits, or the bar in this
; look's colours with the outline not contradicting it.
ReelStillUp(b, geo, p) {
    hits := 0
    Loop 3 {
        VisionGrab(b, geo)
        d := VisionScan(b, p)
        ; shape-read rods (Noiseform, Pinion's Aria) are present when their shape is:
        ; their tubes have no crisp outline to check
        ep := p.kind != "" ? -1 : EdgesPresent(b, geo, p)
        hits += (ep = 1) || (d.bar && d.cover >= 0.8 && ep != 0)
        Sleep 40
    }
    return hits >= 2
}

LogVision(msg) {
    VisionLog.InsertAt(1, FormatTime(, "HH:mm:ss") "  " msg)
    if (VisionLog.Length > 40)
        VisionLog.Pop()
    try LiveLogChanged()
}

ClickShake() {
    cr := ClientRect(RobloxHwnd)
    if !cr
        return
    s := AreaRect("Shake", cr)
    if PixelSearch(&x, &y, s.x1, s.y1, s.x2, s.y2, 0xFFFFFF, Cfg["ShakeTol"]) {
        MouseMove(x + 3, y + 3, 0)
        Sleep 8
        MouseMove(1, 0, 0, "R")
        Click()
    }
}

;------------------------------------------------------------------------------
; Reel control. Holding the mouse accelerates the bar right, releasing lets it
; fall left. The physics style measures those accelerations for each rod and
; brakes on a time-optimal switching curve, so the bar stops with the fish on
; its centre line instead of sliding past it.
;------------------------------------------------------------------------------
Reel(b, geo, base, r) {
    global CurRod, LiveD, LiveP, LiveEp, LiveT, LiveRate
    p := r.prof, w := b.w
    if p.notes
        NoteWatch.Setup(geo, ClientRect(RobloxHwnd))   ; Pinion's Aria: watch the screen above the bar for notes
    if (p.kind = "box" && (zcr := ClientRect(RobloxHwnd)))
        ZoneWatch.Setup(zcr)             ; Noiseform: watch for the zone warning
    edge := w * Cfg["EdgeMargin"] / 100
    physics := (Cfg["ControlStyle"] = "physics")
    autoLag := physics && Cfg["Latency"] = 0
    L := autoLag ? (Cfg["LearnedLag"] > 0 ? Cfg["LearnedLag"] : 40) : Cfg["Latency"]
    brk := Cfg["Braking"] / 100, look := Cfg["Predict"], lead := Cfg["FishLead"] / 100
    est := {aH: 3.0 * w / 1e6, aR: 3.0 * w / 1e6, wH: 0.2, wR: 0.2, nH: 0, nR: 0, fits: 0}
    lag := LagEstimator(L)
    holding := false, tSwitch := QPC() - 1000, sw := [[tSwitch, false]]
    c := -1, v := 0, tC := 0, f := -1, fv := 0, tF := 0, aim := "fish", lastAim := "fish", jumpTo := -1
    lastBl := -2, lastBr := -2, lastFx := -2, tFrame := 0, vmaxSeen := 0
    widths := [], bw := 0, memKey := "", segT := [], segX := []
    t0 := A_TickCount, lastUI := t0, lastDash := 0, frame := 0, ep := -1, good := 0
    lostSince := 0, lastRelearn := 0, phantom := false, why := "", segOK := [], still := [], gone := 0, stale := 0, sawEdges := false
    trail := [], lostHbm := 0, lostAt := -1, wasPresent := false, endWhy := "", snaps := Cfg["ReelSnaps"]
    d := (r.HasOwnProp("d") && IsObject(r.d)) ? r.d : 0
    nIn := 0, nCtr := 0, errSum := 0, nBoth := 0, rateT := A_TickCount, rateF := 0
    SetGauge(0.36, 0.64, 0.5, true)
    while Running {
        if !WinActive("ahk_id " RobloxHwnd) {
            if holding {
                Click("Up")
                holding := false, tSwitch := QPC(), sw.Push([tSwitch, false])
            }
            if !WaitForFocus()
                break
            lastUI := A_TickCount
            continue
        }
        if (frame > 0 || !IsObject(d)) {
            VisionGrab(b, geo)
            d := VisionScan(b, p, f)
            ; Verdant Oath: aim the fish at the green zone, not the bar's centre
            if (p.greenBar && d.bar && d.fish && (gz := (d.HasOwnProp("zc") ? d.zc : GreenZone(b, d))) >= 0)
                d.fx -= gz - (d.bl + d.br) / 2
            ; Noiseform: after the warning, take the bar to the zone it named
            aim := "fish"
            if (p.kind = "box" && ZoneWatch.grab) {
                ZoneWatch.Update(A_TickCount / 1000)
                if ((zt := ZoneWatch.Target(A_TickCount / 1000, b, geo, p)) >= 0)
                    d.fx := zt, d.fish := true, aim := "zone"
            }
            ; Pinion's Aria: catch the falling notes, keeping the fish when both fit
            if p.notes {
                NoteWatch.Update(A_TickCount / 1000)
                if ((nt := NoteWatch.Target(A_TickCount / 1000, d)) >= 0)
                    d.fx := nt, d.fish := true, aim := "note"
            }
        }
        frame++
        if (Mod(frame, 4) = 1)
            ; shape-read rods (Noiseform, Pinion's Aria) are present when their shape is:
            ; their tubes have no crisp outline to check
            ep := p.kind != "" ? -1 : EdgesPresent(b, geo, p)
        now := A_TickCount
        LiveD := d, LiveP := p, LiveEp := ep, LiveT := now     ; for the Live tab
        if (now - rateT >= 1000)
            LiveRate := frame - rateF, rateT := now, rateF := frame
        ; A block of bar colour at the wrong width is scenery, not the bar.
        if (d.bar && bw && Abs(d.br - d.bl + 1 - bw) > Max(6, bw * 0.35))
            d.bar := false
        ; The reel is up while its track outline shows (once learned), or
        ; while the row fits this look's colours. Strong colour evidence
        ; counts while the outline has never matched in this reel: a window
        ; resize or a new reel area leaves a look's stored outline in the
        ; wrong place, and without this the reel would look gone from its
        ; first frame. Once the outline has matched, it decides again, so
        ; leftover scenery after the catch can't hold the reel open.
        if (ep = 1)
            sawEdges := true
        present := (ep = 1) || (ep = -1 && d.cover >= 0.6) || (!sawEdges && ep = 0 && d.bar && d.cover >= 0.85)
        ; What the macro saw this frame, for the reel-end record.
        if snaps {
            trail.Push(Format("{:6d}  outline {:2d}  fit {:.2f}  bar {} {}-{}  fish {} {}  present {}  held {}"
                , now - t0, ep, d.cover, d.bar ? 1 : 0, d.bl, d.br, d.fish ? 1 : 0, Round(d.fx), present ? 1 : 0, holding ? 1 : 0))
            if (trail.Length > 150)
                trail.RemoveAt(1)
            if (wasPresent && !present) {
                if lostHbm
                    DllCall("DeleteObject", "Ptr", lostHbm)
                lostHbm := BandCopy(b), lostAt := now - t0
            }
            wasPresent := present
        }
        ; The outline alone keeps the reel alive: the bar or fish can change
        ; look for a moment (a flash, a glow, the fish on the bar).
        if (present && (d.fish || d.bar || ep = 1)) {
            lastUI := now, good++
            if (good = 30 && p.edgeT = "") {
                e := FindEdges(b, geo)
                if e.ok
                    RememberEdges(p, e, geo), ep := 1
            }
            ; The outline keeps missing while the colours say otherwise:
            ; it was learned somewhere else, so drop it and learn it again.
            stale := (ep = 0) ? stale + 1 : 0
            if (stale = 12) {
                p.edgeT := "", p.edgeB := "", ep := -1, good := 0
                LogVision("Reel outline no longer matched, learning it again")
            }
        }
        if (now - lastUI > 450 || now - t0 > 120000) {
            endWhy := now - t0 > 120000 ? "two-minute limit" : "the reel looked gone for 450 ms"
            break
        }
        ; The moment the reel looks gone, let go and press nothing: in Fisch a
        ; press-and-release after the catch casts the rod again.
        if (!present || !(d.bar || d.fish)) {
            gone++
            if (!present || gone >= 2) {
                if holding
                    Click("Up"), holding := false, tSwitch := QPC(), sw.Push([tSwitch, false]), segT := [], segX := []
                FineSleep(Cfg["ScanDelay"])
                continue
            }
        } else {
            gone := 0
        }
        tq := QPC()
        ; Roblox redraws about 60 times a second while this loop scans faster.
        ; Only a changed picture counts as a new measurement.
        fresh := (d.bl != lastBl || d.br != lastBr || d.fx != lastFx || tq - tFrame >= 25)
        if fresh
            lastBl := d.bl, lastBr := d.br, lastFx := d.fx, tFrame := tq
        while (sw.Length > 2 && sw[2][1] < tq - 450)
            sw.RemoveAt(1)

        ; Bar centre: a tracker that predicts with the learned physics and the
        ; inputs already sent, then corrects toward the measurement.
        if (d.bar && fresh) {
            cm := (d.bl + d.br) / 2
            if (c < 0) {
                c := cm, v := 0
            } else {
                dt := Max(1, tq - tC)
                AccelOver(sw, tC, tq, L, est.aH, est.aR, &dv, &dx)
                cp := c + v * dt + dx
                res := cm - cp
                c := cp + 0.5 * res
                v := v + dv + 0.2 * res / Max(dt, 8)
            }
            tC := tq
            vmaxSeen := Max(vmaxSeen, Abs(v))
            nearWall := d.bl <= 2 || d.br >= w - 3
            ; Some rods change the bar's size during a reel (Pinion's Aria, Verdant
            ; Oath): the width is the median of the latest readings, kept current.
            widths.Push(d.br - d.bl + 1)
            if (widths.Length > 20)
                widths.RemoveAt(1)
            if (memKey != "" && widths.Length >= 12)
                bw := MedianOf(widths)
            if autoLag {
                lag.Observe(sw, tq, cm, c, v, est.aH, est.aR, w, (d.br - d.bl) / 2, vmaxSeen)
                L := lag.value
            }
            ; Samples for the acceleration fit: away from the walls, after the
            ; latest input change has taken effect, and (with Auto latency) only
            ; once the delay has been measured, since a wrong delay skews the fit.
            tau := tq - tSwitch - L
            if (tau >= 8 && !nearWall) {
                segT.Push(tau), segX.Push(cm)
                if (segT.Length >= 6 && segT[segT.Length] - segT[1] >= 250) {
                    ; The scenery guard only acts while the track outline isn't
                    ; confirming the reel: the outline exists only on the real
                    ; reel UI, and input lag or a rod's odd physics can make a
                    ; real bar look like it isn't answering.
                    if (!SegmentAnswers(segT, segX, holding, est, segOK) && ep != 1 && p.kind = "")
                        phantom := true
                    if (physics && (!autoLag || lag.n >= 40))
                        FitSegment(segT, segX, holding, est, w)
                    else
                        segT.Length := 0, segX.Length := 0
                }
            }
            ; A real bar can't sit still for a second while the mouse has been
            ; held or released for a long stretch; scenery can.
            still.Push([tq, cm])
            while (still.Length > 2 && still[2][1] < tq - 1200)
                still.RemoveAt(1)
            if (p.kind = "" && !nearWall && tq - still[1][1] >= 1100 && tq - tSwitch >= 150) {
                lo := 1e9, hi := -1e9
                for s in still
                    lo := Min(lo, s[2]), hi := Max(hi, s[2])
                if (hi - lo < 3 && ep != 1)
                    phantom := true
            }
            if phantom
                break
        } else if (c >= 0 && tq - tC > 300) {
            v := 0
        }

        ; Once the bar width settles, load what was learned about this rod.
        if (memKey = "" && widths.Length >= 12) {
            bw := MedianOf(widths)
            memKey := p.id "@" Round(100 * bw / w)
            if RodMem.Has(memKey) {
                m := RodMem[memKey]
                est.aH := m.aH * w / 1e6, est.aR := m.aR * w / 1e6
                est.wH := est.wR := Min(m.n, 5) * 40
                est.nH := est.nR := Min(m.n, 3)
            }
            UpdateRodInfo(p, bw / w, memKey)
        }

        ; Fish: same kind of tracker, used to lead the target. Switching what
        ; the bar aims at (a zone, a note, the fish) isn't the fish moving, so
        ; the tracker starts afresh instead of reading the jump as speed.
        if (aim != lastAim)
            f := -1, fv := 0, lastAim := aim
        if (d.fish && fresh) {
            if (f < 0) {
                f := d.fx, fv := 0, jumpTo := -1
            } else {
                dt := Max(1, tq - tF)
                fp := f + fv * dt
                res := d.fx - fp
                ; A real fish moves continuously: a reading far from where it
                ; should be only counts once the next reading agrees (a wrong
                ; reading for one frame would otherwise send the bar lunging).
                if (Abs(res) > w * 0.15) {
                    if (jumpTo >= 0 && Abs(d.fx - jumpTo) < w * 0.05)
                        f := d.fx, fv := 0, jumpTo := -1, tF := tq
                    else
                        jumpTo := d.fx
                } else {
                    f := fp + 0.6 * res
                    fv := Clamp(fv + 0.15 * res / Max(dt, 8), -3, 3)
                    jumpTo := -1, tF := tq
                }
            }
            if (tF != tq && f >= 0 && jumpTo < 0)
                tF := tq
        }

        haveFish := d.fish || (f >= 0 && tq - tF < 300)
        if !haveFish {
            hold := v < 0                          ; hover in place
        } else {
            fx := d.fish ? f : f + fv * (tq - tF)
            ; With the fish nearer an end than about half the bar, the bar can't
            ; be centred on it: the best is to sit against that end, so just
            ; hold it there (trying to centre is what bounces it off the end).
            pin := Max(edge, bw ? 0.45 * bw : 0)
            if (fx <= pin)
                hold := false
            else if (fx >= w - pin)
                hold := true
            else if (c < 0)
                hold := fx > w / 2
            else if physics {
                ; Where the bar will be when an input sent now takes effect,
                ; counting the inputs that are still on their way.
                AccelOver(sw, tC, tq + L, L, est.aH, est.aR, &dv, &dx)
                cL := c + v * (tq + L - tC) + dx, vL := v + dv
                hw := bw ? bw / 2 : w * 0.1
                if (cL < hw)
                    cL := hw, vL := Max(0, vL)
                else if (cL > w - hw)
                    cL := w - hw, vL := Min(0, vL)
                eL := (f + lead * fv * (tq + L - tF)) - cL     ; fish relative to bar centre
                de := lead * fv - vL
                ab := de > 0 ? est.aH : est.aR                ; braking acceleration available
                ; Calm zone: with the fish well inside the bar and the two not
                ; drifting apart, just keep the bar still instead of chasing the
                ; exact centre (chasing it is what makes the bar bounce). Narrow
                ; for Verdant Oath, whose green zone needs the precision.
                dz := CalmZoneOn ? hw * (p.greenBar ? 0.06 : 0.2) : 0
                if (Abs(eL) < dz && Abs(de) < w * 0.00025)
                    hold := vL < 0
                else
                    hold := (eL + brk * de * Abs(de) / (2 * ab)) > 0
            } else {
                hold := fx > c + v * (tq - tC) + v * look
            }
        }
        ; Roblox reads input once per frame, so never flip faster than that.
        ; (Requiem snaps the line if inputs come too fast: it has its own minimum)
        if (hold != holding && tq - tSwitch >= (p.minSwitch ? p.minSwitch : 16)) {
            if (!SegmentAnswers(segT, segX, holding, est, segOK) && ep != 1 && p.kind = "") {
                phantom := true
                break
            }
            if (physics && (!autoLag || lag.n >= 40))
                FitSegment(segT, segX, holding, est, w)
            segT := [], segX := []
            Click(hold ? "Down" : "Up")
            holding := hold, tSwitch := tq
            sw.Push([tq, hold])
        }

        if (d.fish && d.bar) {
            half := Max(1, (d.br - d.bl) / 2)
            e := Abs(d.fx - (d.bl + d.br) / 2) / half
            nBoth++, errSum += Min(e, 2)
            nIn += (e <= 1), nCtr += (e <= 0.35)
        }
        if (c >= 0 && now - lastDash >= (Cfg["ReduceMotion"] ? 150 : 45)) {
            lastDash := now
            hw := bw ? bw / 2 : (d.bar ? (d.br - d.bl) / 2 : w * 0.1)
            SetGauge((c - hw) / w, (c + hw) / w, haveFish ? (d.fish ? d.fx : f) / w : -1, true)
            off := (d.fish && d.bar) ? (d.fx - (d.bl + d.br) / 2) / Max(1, (d.br - d.bl) / 2) : ""
            SetLive(off, nBoth ? nCtr / nBoth : "")
        }
        FineSleep(Cfg["ScanDelay"])
    }
    if holding
        Click("Up")
    if (autoLag && lag.n >= 150) {
        Cfg["LearnedLag"] := Round(lag.value)
        Save("LearnedLag")
    }
    if (physics && memKey != "" && est.fits > 0) {
        RememberRod(memKey, est.aH * 1e6 / w, est.aR * 1e6 / w)
        UpdateRodInfo(p, bw / w, memKey)
    }
    if (good >= 30) {
        p.reels++
        if bw
            p.barW := Round(bw / w, 3)
        TouchProfile(p)
    }
    if phantom
        LogVision("Reel ended: the bar stopped answering the mouse (scenery, not the reel)")
    if snaps {
        try SaveReelSnapshot(b, geo, p, trail, lostHbm, lostAt
            , phantom ? "the bar stopped answering the mouse (treated as scenery)" : endWhy != "" ? endWhy : "stopped"
            , A_TickCount - t0, good)
        if lostHbm
            DllCall("DeleteObject", "Ptr", lostHbm)
    }
    return {dur: A_TickCount - t0, frames: nBoth, inside: nBoth ? nIn / nBoth : 0, phantom: phantom, good: good
        , centered: nBoth ? nCtr / nBoth : 0, err: nBoth ? errSum / nBoth : 0, rod: p
        , lag: autoLag ? lag.value : L, lagN: lag.n, loops: frame
        , centeredTxt: nBoth ? Round(100 * nCtr / nBoth) "% of the time" : "n/a"}
}

; Integrates the bar's acceleration over [t1, t2] when each input change
; takes effect `lag` ms after it was sent. sw holds [time, holding] pairs,
; oldest first. Returns the velocity change and the extra displacement
; (beyond constant velocity) reached at t2.
AccelOver(sw, t1, t2, lag, aH, aR, &dv, &dx) {
    dv := 0, dx := 0
    if (t2 <= t1)
        return
    i := sw.Length
    while (i > 1 && sw[i][1] + lag > t1)
        i--
    held := sw[i][2], s := t1, j := i + 1
    loop {
        e := t2
        if (j <= sw.Length && sw[j][1] + lag < t2)
            e := Max(s, sw[j][1] + lag)
        acc := held ? aH : -aR
        dv += acc * (e - s)
        dx += acc * ((t2 - s) ** 2 - (t2 - e) ** 2) / 2
        if (e >= t2)
            return
        held := sw[j][2], s := e, j++
    }
}

; Measures input latency while reeling. For each candidate delay it predicts
; where the bar should be now from where it was about 60 ms ago plus the
; inputs sent since, and keeps a slowly fading squared error. The delay with
; the smallest error, refined between neighbours, wins.
class LagEstimator {
    __New(start) {
        this.cands := [], this.err := [], this.hist := []
        this.n := 0, this.value := start, this.lastObs := 0, this.moved := false
        Loop 21
            this.cands.Push((A_Index - 1) * 10), this.err.Push(0)
    }
    Observe(sw, tq, cm, c, v, aH, aR, w, hw, vmaxSeen) {
        this.hist.Push([tq, c, v])
        while (this.hist.Length > 2 && this.hist[2][1] <= tq - 60)
            this.hist.RemoveAt(1)
        if (tq - this.lastObs < 10)
            return
        s := this.hist[1], H := tq - s[1]
        if (H < 45 || H > 130)
            return
        ; skip moments the model can't explain: walls and top speed
        if (Abs(s[3]) > 0.9 * vmaxSeen || Abs(v) > 0.9 * vmaxSeen)
            return
        if (s[2] - hw < 3 || s[2] + hw > w - 4 || cm - hw < 3 || cm + hw > w - 4)
            return
        this.lastObs := tq
        for k, lk in this.cands {
            AccelOver(sw, s[1], tq, lk, aH, aR, &dv, &dx)
            e := cm - (s[2] + s[3] * H + dx)
            this.err[k] := this.err[k] * 0.996 + e * e
        }
        this.n++
        if (this.n >= 40 && Mod(this.n, 8) = 0) {
            ; The first estimate replaces the stored starting value outright, since
            ; latency can change between sessions; later ones move gradually.
            b := this.Best()
            this.value := this.moved ? Clamp(b, this.value - 20, this.value + 20) : b
            this.moved := true
        }
    }
    Best() {
        bi := 1
        for k, e in this.err
            if (e < this.err[bi])
                bi := k
        best := this.cands[bi]
        if (bi > 1 && bi < this.cands.Length) {
            e0 := this.err[bi - 1], e1 := this.err[bi], e2 := this.err[bi + 1]
            den := e0 - 2 * e1 + e2
            if (den > 0)
                best += 10 * Clamp(0.5 * (e0 - e2) / den, -0.5, 0.5)
        }
        return best
    }
}

; Folds one constant-input stretch of bar motion into the acceleration
; estimates. A fitted curvature's error shrinks with the square of the
; stretch's length, so each stretch counts samples x duration^4; old evidence
; fades so a changed rod is relearned quickly. After a few fits, values more
; than 3x away from the estimate are treated as glitches.
FitSegment(ts, xs, held, est, w) {
    n := ts.Length
    if (n >= 6 && ts[n] - ts[1] >= 50) {
        T := ts[n] - ts[1]
        acc := QuadAccel(ts, xs)
        if (acc != "") {
            acc := held ? acc : -acc
            cur := held ? est.aH : est.aR, cnt := held ? est.nH : est.nR
            lo := cnt >= 3 ? cur / 3 : 0.2 * w / 1e6
            hi := cnt >= 3 ? cur * 3 : 40 * w / 1e6
            if (acc >= lo && acc <= hi) {
                wt := n * (T / 100) ** 4
                if held {
                    W := est.wH * 0.97
                    est.aH := (W * cur + wt * acc) / (W + wt), est.wH := W + wt, est.nH++
                } else {
                    W := est.wR * 0.97
                    est.aR := (W * cur + wt * acc) / (W + wt), est.wR := W + wt, est.nR++
                }
                est.fits++
            }
        }
    }
    ts.Length := 0, xs.Length := 0
}

QuadAccel(ts, xs) {
    n := ts.Length, mean := 0
    for t in ts
        mean += t
    mean /= n
    s1 := 0, s2 := 0, s3 := 0, s4 := 0, y0 := 0, y1 := 0, y2 := 0
    Loop n {
        t := ts[A_Index] - mean, x := xs[A_Index], t2 := t * t
        s1 += t, s2 += t2, s3 += t2 * t, s4 += t2 * t2
        y0 += x, y1 += x * t, y2 += x * t2
    }
    det := n * (s2 * s4 - s3 * s3) - s1 * (s1 * s4 - s3 * s2) + s2 * (s1 * s3 - s2 * s2)
    if (Abs(det) < 1e-6)
        return ""
    det2 := n * (s2 * y2 - y1 * s3) - s1 * (s1 * y2 - y1 * s2) + y0 * (s1 * s3 - s2 * s2)
    return 2 * det2 / det
}

; AutoHotkey's Sleep rounds up to 10-16 ms. The reel loop needs finer
; timing, so it sleeps through Windows (1 ms timer resolution is set at
; startup), then handles waiting messages so hotkeys and the window stay live.
FineSleep(ms) {
    if (ms > 0)
        DllCall("Sleep", "UInt", ms)
    Sleep -1
}

WaitForFocus() {
    if WinActive("ahk_id " RobloxHwnd)
        return true
    ReleaseMouse()
    saved := {kind: Phase.kind, title: Phase.title, detail: Phase.detail}
    SetPhase("pause", "Paused", "Click into Roblox to continue, or press " KeyName(Cfg["ToggleKey"]) " to stop.")
    while Running {
        if !WinExist("ahk_id " RobloxHwnd) {
            ; With auto-reconnect on, a vanished window is a disconnect to
            ; recover from, not a reason to stop.
            if Cfg["AutoReconnect"] {
                FlagDisconnect("The Roblox window closed")
                SetPhase(saved.kind, saved.title, saved.detail)
                return false
            }
            StopMacro("Roblox closed. Reopen Fisch and press " KeyName(Cfg["ToggleKey"]) ".")
            return false
        }
        if WinActive("ahk_id " RobloxHwnd) {
            SetPhase(saved.kind, saved.title, saved.detail)
            return Nap(300)
        }
        Sleep 150
    }
    return false
}

Nap(ms) {
    finish := A_TickCount + ms
    while (Running && A_TickCount < finish)
        Sleep Min(20, Max(1, finish - A_TickCount))
    return Running
}

MouseToCenter() {
    if (cr := ClientRect(RobloxHwnd))
        MouseMove(cr.x + cr.w // 2, cr.y + cr.h // 2, 0)
}

ReleaseMouse() {
    if GetKeyState("LButton")
        Click("Up")
}

;==============================================================================
; Screen reading
;==============================================================================
FindRoblox() {
    for crit in ["ahk_exe RobloxPlayerBeta.exe", "Roblox ahk_class WINDOWSCLIENT"]
        if (hwnd := WinExist(crit))
            return hwnd
    return 0
}

ClientRect(hwnd) {
    try WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch
        return 0
    if (w < 200 || h < 150)
        return 0
    return {x: x, y: y, w: w, h: h}
}

AreaRect(name, cr) {
    x1 := cr.x + Round(Cfg[name "X1"] * cr.w), y1 := cr.y + Round(Cfg[name "Y1"] * cr.h)
    x2 := cr.x + Round(Cfg[name "X2"] * cr.w), y2 := cr.y + Round(Cfg[name "Y2"] * cr.h)
    return {x1: x1, y1: y1, x2: x2, y2: y2, w: Max(8, x2 - x1), h: Max(1, y2 - y1), midY: (y1 + y2) // 2}
}

; One screen row captured into memory, scanned in a single pass.


; Tries each known rod signature on the captured row; learns an unknown one.


; Fish marker = the longest narrow run of fish colour. Bar = the outermost bar
; pixels, or the longest bar-coloured run when the outermost ones are implausible.

; Unknown rod: take the most common colour on the row as the track, the
; longest run of anything else as the bar, and a narrow run that is neither
; track nor bar colour as the fish. Returns a compiled profile or 0.

; Most common colour (5 bits per channel) between two pixel indexes.

; Fraction of the row that differs clearly from the pre-bite snapshot.

QPC() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &now := 0)
    return now * 1000 / freq
}

MedianOf(arr) {
    s := []
    for v in arr
        s.Push(v)
    n := s.Length
    Loop n - 1 {
        i := A_Index + 1, v := s[i], j := i - 1
        while (j >= 1 && s[j] > v)
            s[j + 1] := s[j], j--
        s[j + 1] := v
    }
    return n ? s[(n + 1) // 2] : 0
}

PanelCoversReel(hwnd) {
    cr := ClientRect(hwnd)
    if (!cr || !IsObject(MainGui))
        return false
    try {
        if (WinGetMinMax("ahk_id " MainGui.Hwnd) = -1)
            return false
        WinGetPos(&x, &y, &w, &h, "ahk_id " MainGui.Hwnd)
    } catch {
        return false
    }
    a := AreaRect("Reel", cr)
    return !(x >= a.x2 || x + w <= a.x1 || y >= a.midY + 1 || y + h <= a.midY)
}

UsePhysicalPixels() {
    try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
}

; The minimum time between inputs for the rod in hand, if it has one
; (Requiem loses the fish to fast inputs); 0 for rods that don't care.
QuietRod() {
    for lib in RodLib
        if (lib.id = CurRodLib && lib.HasOwnProp("minSwitch"))
            return lib.minSwitch
    return 0
}


;==============================================================================
; Auto aquarium. Opens Fisch's aquarium panel, scrolls through the fish food
; cards, presses Use on food you own and Buy on shop cards up to the limit,
; then uses what it bought. Food buttons are rectangles outlined in bright
; green; Buy buttons are a purer green than Use buttons.
;==============================================================================
RunAquariumNow() {
    SetTimer(() => RunAquarium(true), -1)
}

RunAquarium(manual := false) {
    if IsGuest()
        return
    global AqNext, AqManual, AqAbort, AqLast, RobloxHwnd
    if manual {
        if (Running || Calibrating || AqManual)
            return
        UsePhysicalPixels()
        h := FindRoblox()
        if !h {
            SetPhase("error", "Roblox isn't open", "Open Fisch first, then run the aquarium.")
            Cue("error")
            return
        }
        RobloxHwnd := h
        AqManual := true, AqAbort := false
        UpdateStartControls()
        try WinActivate("ahk_id " h)
        Sleep 350
    }
    result := ""
    try {
        result := AquariumVisit()
    } catch as err {
        result := "failed: " err.Message
    }
    AqNext := A_TickCount + Cfg["AqEvery"] * 60000
    AqLast := result
    LogEvent("Aquarium " result)
    Alert("aquarium", "Aquarium " result ".")
    if manual {
        AqManual := false
        UpdateStartControls()
        if InStr(result, "failed")
            SetPhase("error", "Aquarium visit failed", SubStr(result, 9))
        else
            SetPhase("idle", "Aquarium visit done", StrTitle(SubStr(result, 1, 1)) SubStr(result, 2) ".")
    }
    RefreshRobloxInfo()
    return result
}

AqAlive() => (Running || AqManual) && !AqAbort

AquariumVisit() {
    SetPhase("aqua", "Tending the aquarium", "Opening the aquarium panel.")
    cr := ClientRect(RobloxHwnd)
    if !cr
        return "failed: the Roblox window isn't ready"
    MouseGetPos(&mx, &my)
    ReleaseMouse()
    aq := AqContext(cr)
    if !AqPanelSure(aq) {
        AqTap(aq.navX, aq.navY)
        AqWaitPanel(aq, true)
    }
    if (!AqPanelSure(aq) && AqAlive())
        AqRecoverRow(aq)
    if !AqPanelSure(aq) {
        MouseMove(mx, my, 0)
        return AqAlive() ? "failed: couldn't find the fish food panel" : "stopped"
    }
    aq.pitch := AqMeasurePitch(aq)
    SetDetail("Using fish food.")
    AqSweep(aq, false)
    if (aq.buys > 0 && AqAlive()) {
        SetDetail("Using the food it just bought.")
        AqSweep(aq, true)
    }
    AqScrollHome(aq)
    if AqPanelSure(aq) {
        SetDetail("Closing the aquarium panel.")
        AqTap(aq.navX, aq.navY)
        AqWaitPanel(aq, false)
    }
    MouseMove(mx, my, 0)
    if !AqAlive() && !aq.uses && !aq.buys
        return "stopped"
    return Format("used {}, bought {}", aq.uses, aq.buys)
}

AqContext(cr) {
    k := Clamp(cr.h / 1080, 0.5, 3)
    x0 := cr.x + Round(cr.w * 0.04), y0 := cr.y + Round(cr.h * 0.33)
    w := Round(cr.w * 0.92), h := Round(cr.h * 0.65)
    return {cr: cr, k: k, x0: x0, y0: y0, g: AreaGrab(w, h), btns: [], hoverX: 0, hoverY: 0, hoverOk: false
        , navX: UiSpot("aquariums", cr).x, navY: UiSpot("aquariums", cr).y
        , pitch: 0, uses: 0, buys: 0, done: 0}
}

class AreaGrab {
    __New(w, h) {
        this.w := w := Max(1, w), this.h := h := Max(1, h)
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
        NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
        this.dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        this.bmp := DllCall("CreateDIBSection", "Ptr", this.dc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        this.bits := bits
        this.old := DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.bmp, "Ptr")
    }
    Grab(x, y) {
        sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        DllCall("BitBlt", "Ptr", this.dc, "Int", 0, "Int", 0, "Int", this.w, "Int", this.h
            , "Ptr", sdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    }
    __Delete() {
        DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.old)
        DllCall("DeleteObject", "Ptr", this.bmp)
        DllCall("DeleteDC", "Ptr", this.dc)
    }
}

AqScan(aq) {
    aq.g.Grab(aq.x0, aq.y0)
    n := AqFindButtons(aq)
    if n {
        aq.hoverX := aq.btns[1].x, aq.hoverY := aq.btns[1].y, aq.hoverOk := true
    }
    return n
}

; Green edge pixel: G at least 240 and B between 100 and 160.
AqFindButtons(aq) {
    g := aq.g, pb := g.bits, W := g.w, H := g.h, k := aq.k
    minW := Round(55 * k), maxW := Round(W * 0.45), minH := Round(16 * k), maxH := Round(96 * k)
    tol := Max(3, Round(6 * k)), stepX := Max(4, Round(8 * k))
    lines := [], prev := -99, y := 0
    while (y < H) {
        off := y * W * 4, hits := 0, x := 0
        while (x < W) {
            c := NumGet(pb, off + x * 4, "UInt")
            if (((c >> 8) & 255) >= 240 && (c & 255) >= 100 && (c & 255) <= 160) {
                hits++
                if (hits >= 6)
                    break
            }
            x += stepX
        }
        if (hits >= 6) {
            if (y - prev > 2)
                lines.Push(y)
            prev := y
        }
        y++
    }
    cache := Map(), seen := Map(), btns := []
    for ia, ya in lines {
        ra := AqRuns(pb, W, ya, minW, cache)
        ib := ia + 1
        while (ib <= lines.Length) {
            yb := lines[ib], ib++
            gap := yb - ya
            if (gap < minH)
                continue
            if (gap > maxH)
                break
            rb := AqRuns(pb, W, yb, minW, cache)
            for sa in ra {
                if (sa[2] - sa[1] > maxW)
                    continue
                for sb in rb {
                    if (Abs(sa[1] - sb[1]) > tol || Abs(sa[2] - sb[2]) > tol)
                        continue
                    key := ((sa[1] + sa[2]) // 2) "_" ya
                    if seen.Has(key)
                        continue
                    seen[key] := 1
                    if (b := AqMakeButton(aq, pb, W, sa, ya, yb))
                        btns.Push(b)
                }
            }
        }
    }
    ; left to right
    n := btns.Length
    Loop n - 1 {
        i := A_Index + 1, b := btns[i], j := i - 1
        while (j >= 1 && btns[j].x > b.x)
            btns[j + 1] := btns[j], j--
        btns[j + 1] := b
    }
    aq.btns := btns
    return n
}

AqRuns(pb, W, y, minW, cache) {
    if cache.Has(y)
        return cache[y]
    runs := [], rs := -1, off := y * W * 4
    Loop W + 1 {
        x := A_Index - 1, on := false
        if (x < W) {
            c := NumGet(pb, off + x * 4, "UInt")
            on := ((c >> 8) & 255) >= 240 && (c & 255) >= 100 && (c & 255) <= 160
        }
        if (on && rs < 0)
            rs := x
        else if (!on && rs >= 0) {
            if (x - rs >= minW)
                runs.Push([rs, x])
            rs := -1
        }
    }
    cache[y] := runs
    return runs
}

AqMakeButton(aq, pb, W, run, ya, yb) {
    sum := 0, n := 0, off := ya * W * 4, x := run[1]
    while (x < run[2]) {
        c := NumGet(pb, off + x * 4, "UInt")
        gg := (c >> 8) & 255, b := c & 255
        if (gg >= 240 && b >= 100 && b <= 160)
            sum += gg - ((c >> 16) & 255), n++
        x++
    }
    if (n < 12)
        return 0
    return {x: aq.x0 + (run[1] + run[2]) // 2, y: aq.y0 + (ya + yb) // 2, kind: (sum / n > 60) ? "buy" : "use"
        , w: run[2] - run[1], h: yb - ya}
}

AqPanelSure(aq) {
    Loop 3 {
        if (AqScan(aq) > 0)
            return true
        if !AqAlive()
            return false
        Sleep 150
    }
    return false
}

AqWaitPanel(aq, want) {
    start := A_TickCount, cap := Cfg["AqOpenWait"] + 3000
    while AqAlive() {
        Sleep 150
        if ((AqScan(aq) > 0) = want)
            return true
        if (A_TickCount - start >= cap)
            return false
    }
    return false
}

AqTap(x, y) {
    MouseMove(x, y, 0)
    Sleep 55
    Click()
}

AqWheel(aq, n, dir) {
    if (!aq.hoverOk && AqScan(aq) < 1)
        return false
    MouseMove(aq.hoverX, aq.hoverY, 0)
    Sleep 60
    Loop n {
        Click(dir > 0 ? "WheelDown" : "WheelUp")
        Sleep 30
    }
    Sleep 130
    return true
}

AqLeftX(aq) => aq.btns.Length ? aq.btns[1].x : -99999

AqScrollHome(aq) {
    last := -99999
    Loop 20 {
        if (!AqAlive() || !AqWheel(aq, Cfg["AqScrollSteps"], -1))
            return false
        AqScan(aq)
        cur := AqLeftX(aq)
        if (aq.btns.Length && cur = last)
            return true
        last := cur
    }
    return true
}

; The row may be scrolled out of view when the panel opens; nudge it back.
AqRecoverRow(aq) {
    aq.hoverX := aq.cr.x + Round(aq.cr.w * 0.5), aq.hoverY := aq.cr.y + Round(aq.cr.h * 0.62), aq.hoverOk := true
    spent := 0
    Loop 6 {
        if !AqWheel(aq, 5, -1)
            break
        spent += 5
        if (AqScan(aq) >= 1)
            return true
    }
    if spent
        AqWheel(aq, spent, 1)
    aq.hoverOk := false
    return false
}

AqMeasurePitch(aq) {
    best := 0
    if (AqScan(aq) >= 2) {
        Loop aq.btns.Length - 1
            best := Max(best, aq.btns[A_Index + 1].x - aq.btns[A_Index].x)
    }
    if (best < 20) {
        wmax := 0
        for b in aq.btns
            wmax := Max(wmax, b.w)
        best := Max(Round(60 * aq.k), Round(wmax * 1.4))
    }
    return best
}

; Walks the card row left to right. Cards are tracked by content position
; (screen x plus how far the row has scrolled) so none is pressed twice.
AqSweep(aq, useOnly) {
    AqScrollHome(aq)
    shift := 0, seenMax := -999999, half := Max(20, aq.pitch // 2), stall := 0, pressed := []
    AqScan(aq)
    Loop 60 {
        if (!AqAlive() || aq.done >= Cfg["AqMaxUses"])
            break
        hitShop := false
        list := []
        for b in aq.btns
            list.Push(b)
        for b in list {
            if (!AqAlive() || aq.done >= Cfg["AqMaxUses"])
                break
            cx := b.x + shift
            if (cx <= seenMax + half || AqNear(pressed, cx, half))
                continue
            seenMax := cx
            if (b.kind = "buy") {
                if useOnly {
                    hitShop := true
                    break
                }
                if (aq.buys >= Cfg["AqMaxBuys"])
                    continue
                aq.buys++
            } else {
                aq.uses++
            }
            aq.done++
            pressed.Push(cx)
            AqTap(b.x, b.y)
            Sleep Cfg["AqStepDelay"]
        }
        if hitShop
            break
        AqScan(aq)
        prevLeft := AqLeftX(aq), oldX := []
        for b in aq.btns
            oldX.Push(b.x)
        if !AqWheel(aq, 1, 1)
            break
        if (AqScan(aq) < 1)
            break
        newX := []
        for b in aq.btns
            newX.Push(b.x)
        shift += AqShiftBetween(oldX, newX, aq.pitch)
        if (AqLeftX(aq) = prevLeft) {
            if (++stall >= 3)
                break
        } else {
            stall := 0
        }
    }
}

; How far the row moved left between two scans. If most buttons sit where
; they were, the row didn't move (the end of the row). Otherwise the median of
; plausible differences. When nothing lines up the answer is 0: an unclear
; scroll can then only cause a skipped card, never a second press.
AqShiftBetween(oldX, newX, pitch) {
    if (!oldX.Length || !newX.Length || pitch < 20)
        return 0
    same := 0
    for nx in newX {
        for ox in oldX {
            if (Abs(ox - nx) <= 2) {
                same++
                break
            }
        }
    }
    if (same * 2 >= newX.Length)
        return 0
    ds := [], hi := Round(pitch * 0.92)
    for ox in oldX
        for nx in newX
            if (ox - nx >= 3 && ox - nx <= hi)
                ds.Push(ox - nx)
    return ds.Length ? MedianOf(ds) : 0
}

AqNear(list, x, tol) {
    for v in list
        if (Abs(v - x) < tol)
            return true
    return false
}

AqInfoText() {
    if !Cfg["AqAuto"]
        return "Off"
    if (AqNext = 0)
        return "Next visit when fishing starts"
    mins := Ceil((AqNext - A_TickCount) / 60000)
    return mins > 0 ? "Next visit in " mins " min" : "Due now"
}

AqTileText() => Cfg["AqAuto"] ? "On, every " Cfg["AqEvery"] " min" : "Off. Feeds fish between catches"

;==============================================================================
; Window. A sidebar of tabs on the left (the basics, or the Advanced set
; behind a toggle), the page on the right in one column, and a slim status
; line along the bottom. While fishing, the window steps aside for a small
; panel in the top-right corner (class Hud). The coloured areas are painted
; in WM_ERASEBKGND, so no control ever sits on top of another.
;==============================================================================
BuildGui() {
    global MainGui, UiReady, UI, Clickables, Pages, FocusGlobal, DescOf, EditCtls
    global Steppers, Toggles, KeyBtns, SegCtls, Swatches, Choices, FocusIdx, FocusOn, Hover, ColX, RowBase
    UiReady := false
    UI := {tabs: Map(), navRows: Map(), navMode: "basic", menuBtns: Map(), units: Map(), sbLeft: [], sbRight: []
        , gX: 0, gW: 100, gLive: -1, phaseColor: "", dash: [], rodRows: [], totemRows: [], liveVals: Map(), hiddenForHud: false}
    Clickables := Map(), Pages := Map(), FocusGlobal := [], DescOf := Map(), EditCtls := Map()
    Steppers := Map(), Toggles := Map(), KeyBtns := Map(), SegCtls := Map(), Swatches := Map(), Choices := Map()
    FocusIdx := 0, FocusOn := false, Hover := 0, ColX := PAGE_X - PAD, RowBase := ROW_Y0
    for t in TabNames
        Pages[t] := {ctls: [], focus: [], desc: ""}
    MainGui := Gui("-Caption +MinimizeBox" (Cfg["OnTop"] ? " +AlwaysOnTop" : ""), APP_NAME)
    MainGui.BackColor := Pal.content
    MainGui.MarginX := 0, MainGui.MarginY := 0
    MainGui.OnEvent("Close", (*) => ExitApp())
    SwitchArt.Build()
    BuildSidebar()
    BuildChrome()
    BuildStatusBar()
    BuildHome(), BuildFishing(), BuildTotems(), BuildAquarium(), BuildSovereign(), BuildAlerts(), BuildReconnect(), BuildSettings()
    BuildRods(), BuildLive(), BuildReel(), BuildTiming(), BuildMore()
    ColX := PAGE_X - PAD, RowBase := ROW_Y0
    UI.desc := AddT(0, PAGE_X, 354, LEFT_W, 32, "", "body", 9, Pal.dim, Pal.content)
    UI.ring := []
    Loop 4
        UI.ring.Push(MainGui.Add("Text", "x0 y0 w1 h1 Hidden Background" Pal.focus))
    BuildMenus()
    LockPanel.Build()
    UiReady := true
    RodsChanged(), TotemsChanged()
}

NavIcon(name) {
    static icons := Map("Home", 0xE80F, "Fishing", 0xE768, "Totems", 0xE706, "Aquarium", 0xE71D, "Sovereign", 0xE945
        , "Alerts", 0xE715, "Reconnect", 0xE72C, "Settings", 0xE713, "Rods", 0xE8B7, "Live", 0xE9D9, "Reel", 0xE7C3
        , "Timing", 0xE823, "More", 0xE712)
    return icons.Has(name) ? icons[name] : 0xE76C
}

; The sidebar: the logo, the tabs' icons and the start button, in a narrow
; strip. Hovering it opens the full sidebar (class Flyout) over the page.
BuildSidebar() {
    UI.logoHbm := 0
    if (src := LogoImage("icon")) {
        UI.logoHbm := GpScaled(src, ZS(24), ZS(24), "0x" Pal.strip)
        if UI.logoHbm
            MainGui.Add("Picture", Format("x{} y{} w{} h{}", ZS((SIDEBAR_W - 24) // 2), ZS(15), ZS(24), ZS(24)), "HBITMAP:*" UI.logoHbm)
    }
    if !UI.logoHbm
        AddT(0, 4, 10, SIDEBAR_W - 8, 34, "F", "display", 14, Pal.text, Pal.strip, "Center 0x200")
    y := 56
    for i, name in BasicTabs
        NavRow(name, name, y + (i - 1) * NAV_H, "basic")
    UI.navAdv := NavRow("__adv", "Advanced", y + BasicTabs.Length * NAV_H + 6, "basic", 0xE76C)
    UI.navBack := NavRow("__back", "Back", y, "adv", 0xE76B)
    for i, name in AdvTabs
        NavRow(name, name, y + i * NAV_H + 6, "adv")
    ; the active tab's mark: one bar that slides from tab to tab
    UI.navInd := AddT(0, 3, y, 3, NAV_H - 4, "", "body", 9, Pal.text, Pal.accent)
    UI.startBtn := AddT(0, 8, 364, SIDEBAR_W - 16, 36, "", HasIconFont ? "icon" : "body", HasIconFont ? 12 : 11, Pal.ink, Pal.accent, "Center 0x200")
    Clickables[UI.startBtn.Hwnd] := {kind: "btn", fn: (*) => ToggleMacro(), obj: UI.startBtn, bg: Pal.accent, hv: Pal.accentHi}
    FocusGlobal.Push({ctls: [UI.startBtn], name: "Start or stop fishing", act: () => ToggleMacro(), adj: 0, value: 0, desc: ""})
    Flyout.Build()
}

; One sidebar entry: its icon (the flyout shows the label beside it). Without
; the icon font, the label's first letters stand in for the icon.
NavRow(name, label, y, mode, icon := 0) {
    h := NAV_H - 4
    txt := HasIconFont ? Chr(icon ? icon : NavIcon(name)) : SubStr(label, 1, 2)
    ic := AddT(0, 8, y, SIDEBAR_W - 16, h, txt, HasIconFont ? "icon" : "body", 10, Pal.dim, Pal.strip, "Center 0x200")
    e := {kind: "tab", name: name, obj: ic, objs: [ic], bg: Pal.strip, hv: Pal.fieldHi}
    Clickables[ic.Hwnd] := e
    row := {icon: ic, mode: mode, entry: e, y: y, label: label, glyph: txt}
    UI.navRows[name] := row
    if (SubStr(name, 1, 2) != "__")
        UI.tabs[name] := ic
    FocusGlobal.Push({ctls: [ic], name: label (SubStr(name, 1, 2) = "__" ? "" : " tab"), act: NavPress.Bind(name), adj: 0, value: 0, desc: "", navMode: mode})
    return row
}

NavPress(name, *) {
    if (name = "__adv")
        return SetNavMode("adv")
    if (name = "__back")
        return SetNavMode("basic")
    SwitchTab(name)
}

; Shows the basic tabs or the Advanced set in the sidebar.
SetNavMode(mode) {
    if (UI.navMode = mode)
        return
    UI.navMode := mode
    PaintTabs()
    Say(mode = "adv" ? "Advanced tabs" : "Basic tabs")
}

BuildChrome() {
    UI.btnMin := ChromeBtn(IconOr(Chr(0xE921), "–"), (*) => MainGui.Minimize())
    UI.btnClose := ChromeBtn(IconOr(Chr(0xE8BB), "×"), (*) => ExitApp(), true)
}

ChromeBtn(text, fn, isClose := false) {
    b := AddRaw(0, 0, 0, ZS(40), ZS(30), text, HasIconFont ? "icon" : "body", HasIconFont ? 9 : 12, Pal.dim, Pal.content, "Center 0x200")
    ; the close button's hover is red, except in the black-and-white theme
    hv := isClose ? (Pal.HasOwnProp("mono") ? "FFFFFF" : "C42B1C") : Pal.field
    hvText := isClose ? (Pal.HasOwnProp("mono") ? "000000" : "FFFFFF") : ""
    Clickables[b.Hwnd] := {kind: "btn", fn: fn, obj: b, bg: Pal.content, hv: hv, hvText: hvText}
    return b
}

BuildStatusBar() {
    UI.sbDot := SbItem(PAGE_X - 4, 14, "●", Pal.dim, "0x200")
    UI.sbStatus := SbItem(PAGE_X + 12, 200, "Ready", Pal.text, "0x200")
    UI.sbCasts := SbItem(212, 70, "Casts 0", Pal.text, "0x200", true)
    UI.sbReels := SbItem(140, 70, "Reels 0", Pal.text, "0x200", true)
    UI.sbTime := SbItem(68, 58, "0:00:00", Pal.text, "0x200", true)
}

SbItem(x, w, text, color, extra, right := false) {
    c := AddT(0, right ? 0 : x, 0, w, STATUS_H, text, "body", 9, color, Pal.bar, extra)
    (right ? UI.sbRight : UI.sbLeft).Push({ctl: c, off: x, dy: 0})
    return c
}

;------------------------------------------------------------------------------
; Pages. One column; the basics on the main tabs, fine-tuning under Advanced.
;------------------------------------------------------------------------------
; Home is the dashboard: what's happening, the fish against the bar, the rod,
; the next job, Roblox, and recent events.
BuildHome() {
    AddT("Home", PAGE_X, 12, LEFT_W - 90, 30, APP_NAME, "display", 15, Pal.text, Pal.content, "0x200")
    UI.hDot := AddT("Home", PAGE_X, 44, 16, 20, "●", "body", 9, Pal.dim, Pal.content, "0x200")
    UI.hRbx := AddT("Home", PAGE_X + 16, 44, LEFT_W - 16, 20, "Looking for Roblox", "body", 9, Pal.dim, Pal.content, "0x200")
    x := PAGE_X, w := LEFT_W
    UI.dStatus := AddT("Home", x, 72, w, 36, "Ready", "display", 18, Pal.text, Pal.content, "0x200")
    UI.dDetail := AddT("Home", x, 108, w, 34, IdleHint(), "body", 9, Pal.dim, Pal.content)
    UI.gFish := AddT("Home", x + 170, 146, 3, 7, "", "body", 9, Pal.text, Pal.faint)
    UI.gL := AddT("Home", x, 155, 10, 12, "", "body", 9, Pal.text, Pal.field)
    UI.gBar := AddT("Home", x + 10, 155, 10, 12, "", "body", 9, Pal.text, Pal.faint)
    UI.gR := AddT("Home", x + 20, 155, 10, 12, "", "body", 9, Pal.text, Pal.field)
    UI.gCtr := AddT("Home", x + 170, 169, 2, 5, "", "body", 9, Pal.text, Pal.faint)
    UI.mOffL := AddT("Home", x, 180, 76, 22, "Fish offset", "body", 9, Pal.dim, Pal.content, "0x200")
    UI.mOff := AddT("Home", x + 76, 180, 60, 22, "–", "num", 11, Pal.text, Pal.content, "0x200")
    UI.mCtrL := AddT("Home", x + w // 2, 180, 66, 22, "Centered", "body", 9, Pal.dim, Pal.content, "0x200")
    UI.mCtr := AddT("Home", x + w // 2 + 66, 180, 60, 22, "–", "num", 11, Pal.text, Pal.content, "0x200")
    UI.sep1 := AddT("Home", x, 208, w, 1, "", "body", 9, Pal.dim, Pal.seam)
    rows := [["lRod", "iRod", "Rod", RodInfoText], ["lPhys", "iPhys", "Reel", "–"], ["lAq", "iAq", "Next job", NextJobText()], ["lRbx", "iRbx", "Roblox", "Checking"]]
    for i, r in rows {
        yy := 214 + (i - 1) * 20
        UI.%r[1]% := AddT("Home", x, yy, 80, 20, r[3], "body", 9, Pal.dim, Pal.content, "0x200")
        UI.%r[2]% := AddT("Home", x + 80, yy, w - 80, 20, r[4], "body", 9, Pal.text, Pal.content, "0x200")
    }
    UI.sep2 := AddT("Home", x, 298, w, 1, "", "body", 9, Pal.dim, Pal.seam)
    UI.evHead := AddT("Home", x, 304, w, 18, "Recent", "body", 9, Pal.dim, Pal.content)
    UI.events := AddT("Home", x, 322, w, 62, EventsText(), "body", 9, Pal.text, Pal.content)
}

BuildFishing() {
    PageHead("Fishing", "Fishing", "Rod key and how the shake is done.")
    KeyBtn("Fishing", 0, "RodKey", "Rod slot key", "The hotbar key for your rod. Totems and recharges also use it to put the rod back.")
    Toggle("Fishing", 1, "RodReequip", "Re-equip after 3 misses", "Presses the rod slot key twice after three casts in a row get no bite, to clear a stuck bobber.")
    Seg("Fishing", 2, "ShakeMode", "Shake method", [["Navigation", "Navigation"], ["Click", "Click"]]
        , "Navigation presses Enter, which needs Fisch's shake mode set to Navigation. Click hunts for the white shake button.")
    ActionBtn("Fishing", 3, "Set reel area", (*) => StartCalibrate("Reel"), "Freeze the screen while a reel bar is up and drag a box just inside the track.")
    ActionBtn("Fishing", 4, "Set shake area", (*) => StartCalibrate("Shake"), "Click mode only: freeze the screen and drag a box where shake buttons pop up.")
    Toggle("Fishing", 5, "ShowAreas", "Show scan areas on Roblox", "Draws the reel and shake areas and the aquarium button's spot on the Roblox window.")
    Pages["Fishing"].desc := "Equip your rod, face the water and press Start."
}

; Scheduled totems (up to six), with the switch that runs them.
BuildTotems() {
    PageHead("Totems", "Totems", "Uses your totems between catches.")
    Toggle("Totems", 0, "TotemAuto", "Use totems while fishing", "Between catches, uses each scheduled totem when it's due, then puts the rod back in hand.")
    Loop TOTEM_MAX {
        i := A_Index, y := RowBase + i * ROW_H, x := PAGE_X
        on := AddT("Totems", x, y, 40, 28, "On", "body", 9, Pal.ink, Pal.accent, "Center 0x200")
        nm := AddT("Totems", x + 46, y, 122, 28, "", "body", 10, Pal.text, Pal.content, "0x200")
        nt := AddT("Totems", x + 170, y, 52, 28, "Night", "body", 9, Pal.dim, Pal.field, "Center 0x200")
        ky := AddT("Totems", x + 228, y, 52, 28, "", "num", 10, Pal.text, Pal.field, "Center 0x200")
        mi := AddT("Totems", x + 288, y, 24, 28, "−", "body", 12, Pal.dim, Pal.field, "Center 0x200")
        ev := AddT("Totems", x + 314, y, 38, 28, "", "num", 10, Pal.text, Pal.field, "Center 0x200")
        pl := AddT("Totems", x + 354, y, 24, 28, "+", "body", 12, Pal.dim, Pal.field, "Center 0x200")
        un := AddT("Totems", x + 382, y, 34, 28, "min", "body", 9, Pal.dim, Pal.content, "0x200")
        dl := AddT("Totems", x + 424, y, 28, 28, "×", "body", 12, Pal.dim, Pal.field, "Center 0x200")
        Clickables[on.Hwnd] := {kind: "tt", op: "on", i: i, obj: on}
        Clickables[nm.Hwnd] := {kind: "tt", op: "name", i: i, obj: nm}
        Clickables[nt.Hwnd] := {kind: "tt", op: "night", i: i, obj: nt}
        Clickables[ky.Hwnd] := {kind: "tt", op: "key", i: i, obj: ky, bg: Pal.field, hv: Pal.fieldHi}
        Clickables[mi.Hwnd] := {kind: "tt", op: "less", i: i, obj: mi, bg: Pal.field, hv: Pal.fieldHi}
        Clickables[pl.Hwnd] := {kind: "tt", op: "more", i: i, obj: pl, bg: Pal.field, hv: Pal.fieldHi}
        Clickables[dl.Hwnd] := {kind: "tt", op: "del", i: i, obj: dl, bg: Pal.field, hv: Pal.fieldHi}
        DescOf[on.Hwnd] := "Turns this totem's schedule on or off."
        DescOf[nm.Hwnd] := "Click to change which totem this is."
        DescOf[nt.Hwnd] := "Night-only totems wait for night, using a scheduled Sundial first."
        DescOf[ky.Hwnd] := "The hotbar key that holds this totem. Click, then press the key."
        for c in [mi, ev, pl, un]
            DescOf[c.Hwnd] := "Minutes between uses."
        DescOf[dl.Hwnd] := "Removes this totem from the schedule."
        AddFocus("Totems", [on, nm], "Totem " i, TotemOp.Bind("on", i), TotemAdj.Bind(i), TotemSpoken.Bind(i), "Space turns it on or off. Arrow keys change the minutes.")
        AddFocus("Totems", [ky], "Totem " i " hotbar key", TotemOp.Bind("key", i), 0, () => "", "Press Enter, then the hotbar key.")
        UI.totemRows.Push({on: on, name: nm, night: nt, key: ky, less: mi, every: ev, more: pl, unit: un, del: dl})
    }
    half := (LEFT_W - 12) // 2
    UI.btnAddTotem := ActionBtn("Totems", 7, "+  Add a totem", (*) => SetTimer(OpenTotemMenu.Bind(0), -1), "Pick a totem to schedule. Aurora and Blue Moon need night.", PAD, half)
    ActionBtn("Totems", 7, "Use totems now", (*) => SetTimer(UseTotemsNow, -1), "Uses every scheduled totem once, right away, so you can check the keys.", PAD + half + 12, half)
    Pages["Totems"].desc := ""
}

BuildAquarium() {
    PageHead("Aquarium", "Aquarium", "Feeds your aquarium between catches.")
    Toggle("Aquarium", 0, "AqAuto", "Auto aquarium", "Between catches, opens the Aquariums tab on a timer, uses your fish food and buys more up to the limit.")
    Stepper("Aquarium", 1, "AqEvery")
    Stepper("Aquarium", 2, "AqMaxUses")
    Stepper("Aquarium", 3, "AqMaxBuys")
    ActionBtn("Aquarium", 4, "Run now", (*) => RunAquariumNow(), "Runs one visit right away so you can watch it work. Press your start key to stop it.")
    Pages["Aquarium"].desc := ""
}

BuildSovereign() {
    PageHead("Sovereign", "Sovereign", "Recharges Sovereign with plain Enchant Relics.")
    Toggle("Sovereign", 0, "SovAuto", "Recharge Sovereign power", "Every few reels, opens the inventory, searches for a plain Enchant Relic (no mutation), holds it, and clicks Enchant Rod and Confirm.")
    Stepper("Sovereign", 1, "SovEvery")
    Stepper("Sovereign", 2, "SovCount")
    ActionBtn("Sovereign", 3, "Recharge now", (*) => SetTimer(RechargeNow, -1), "Runs one recharge right away so you can watch it work.")
    UI.sovStatus := AddT("Sovereign", PAGE_X, RowBase + 4 * ROW_H + 4, LEFT_W, 50, "", "body", 9, Pal.dim, Pal.content)
    Pages["Sovereign"].desc := "Mutated relics are never used."
}

BuildAlerts() {
    PageHead("Alerts", "Alerts", "Discord messages about your session.")
    EditRow("Alerts", 0, "HookUrl", "Webhook link", "In Discord: Server Settings, Integrations, Webhooks, New Webhook, Copy Webhook URL. Paste it here.")
    EditRow("Alerts", 1, "HookUser", "Ping user ID", "Optional. Your Discord user ID, so problems and disconnects ping you.")
    Toggle("Alerts", 2, "HookErrors", "Problems", "A message, with a screenshot, when fishing stops because something went wrong.")
    Toggle("Alerts", 3, "HookDisconnect", "Disconnects and rejoins", "A message when Roblox disconnects and when the macro gets back in.")
    Toggle("Alerts", 4, "HookStart", "Started and stopped", "A message when fishing starts and when it stops normally.")
    Toggle("Alerts", 5, "HookJobs", "Aquarium, totems, recharges", "A message each time one of the between-catch jobs runs.")
    Stepper("Alerts", 6, "HookSummary")
    half := (LEFT_W - 12) // 2
    ActionBtn("Alerts", 7, "Send test message", (*) => SendTestAlert(), "Sends a test message to your webhook.", PAD, half)
    UI.hookStatus := AddT("Alerts", PAGE_X + half + 12, RowBase + 7 * ROW_H, half, 30, "", "body", 9, Pal.dim, Pal.content, "0x200")
    Pages["Alerts"].desc := ""
}

BuildReconnect() {
    PageHead("Reconnect", "Reconnect", "Rejoins after a disconnect.")
    Toggle("Reconnect", 0, "AutoReconnect", "Rejoin after a disconnect", "Watches Roblox's own log for a lost connection, then closes Roblox, rejoins and resumes fishing.")
    EditRow("Reconnect", 1, "RejoinLink", "Rejoin link", "Where to rejoin. Fisch by default. A private server link works if it has privateServerLinkCode in it.")
    Stepper("Reconnect", 2, "RejoinWait")
    Stepper("Reconnect", 3, "RejoinMax")
    Toggle("Reconnect", 4, "RejoinResume", "Equip the rod and resume", "After rejoining, clicks the game once and presses your rod key before fishing again.")
    ActionBtn("Reconnect", 5, "Check the Roblox log now", (*) => PaintReconnectStatus(), "Shows which Roblox log the watcher reads and the last disconnect line it saw.")
    UI.recStatus := AddT("Reconnect", PAGE_X, RowBase + 6 * ROW_H + 4, LEFT_W, 50, "", "body", 9, Pal.dim, Pal.content)
    Pages["Reconnect"].desc := "You may rejoin away from your fishing spot."
}

BuildSettings() {
    PageHead("Settings", "Settings", "Look, keys and updates.")
    Choice("Settings", 0, "Theme", "Theme", [["Black", "Black"], ["Dark", "Dark"], ["Light", "Light"], ["High contrast", "High contrast"]]
        , "Black uses only black, white and grays. Dark suits dim rooms, Light bright ones. High contrast uses black, white, yellow and cyan.")
    Stepper("Settings", 1, "Zoom")
    Toggle("Settings", 2, "MiniHud", "Small panel while fishing", "While fishing, hides this window and shows a small panel in the top-right corner with what's happening and a Stop button.")
    Toggle("Settings", 3, "OnTop", "Keep window on top", "Keeps this window above Roblox.")
    KeyBtn("Settings", 4, "ToggleKey", "Start and stop", "Works in any window, including Roblox.")
    KeyBtn("Settings", 5, "ExitKey", "Quit", "Closes the macro from any window.")
    half := (LEFT_W - 12) // 2
    ActionBtn("Settings", 6, "Check for updates", (*) => SetTimer(CheckForUpdate.Bind(false), -1), "Checks the update link for a newer version and shows what changed.", PAD, half)
    ActionBtn("Settings", 6, "What's new", (*) => ShowWhatsNew(), "Shows the changes in this version.", PAD + half + 12, half)
    EditRow("Settings", 7, "UpdateUrl", "Update link", "The address of the update file (update.json). Whoever controls it controls what the macro installs.")
    Pages["Settings"].desc := ""
}

; Advanced: the rod looks the macro has learned.
BuildRods() {
    PageHead("Rods", "Rod", "The rod in your hotbar and the reel style used for it.")
    AddT("Rods", PAGE_X, RowBase, 130, 28, "Equipped rod", "body", 10, Pal.dim, Pal.content, "0x200")
    UI.rodName := AddT("Rods", PAGE_X + 130, RowBase, LEFT_W - 130, 28, "–", "body", 10, Pal.text, Pal.content, "0x200")
    AddT("Rods", PAGE_X, RowBase + ROW_H, 130, 28, "Reel style", "body", 10, Pal.dim, Pal.content, "0x200")
    UI.rodStyle := AddT("Rods", PAGE_X + 130, RowBase + ROW_H, LEFT_W - 130, 28, "–", "body", 10, Pal.text, Pal.content, "0x200")
    ActionBtn("Rods", 2, "Read the rod now", (*) => SetTimer(ReadRodName.Bind(true), -1), "Reads the rod's name from its hotbar slot, using your rod key's slot.")
    ; a rod typed by hand (small mistakes corrected), in place of the hotbar's
    y := RowBase + 3 * ROW_H
    AddT("Rods", PAGE_X, y, 130, 28, "Type a rod", "body", 10, Pal.dim, Pal.content, "0x200")
    UI.rodEdit := AddEdit("Rods", PAGE_X + 130, y, LEFT_W - 130 - 140, 28, Cfg["RodManual"], "rodtype")
    for it in [["Use", 0, (*) => UseTypedRod()], ["Auto", 70, (*) => ClearTypedRod()]] {
        b := AddT("Rods", PAGE_X + LEFT_W - 134 + it[2], y, 64, 28, it[1], "body", 10, Pal.text, Pal.field, "Center 0x200")
        Clickables[b.Hwnd] := {kind: "btn", fn: it[3], obj: b, bg: Pal.field, hv: Pal.fieldHi}
        DescOf[b.Hwnd] := it[1] = "Use" ? "Uses the rod you typed (Enter does the same). It stays until you press Auto." : "Forgets the typed rod and reads the rod from the hotbar again."
    }
    DescOf[UI.rodEdit.Hwnd] := "Type your rod's name. Small mistakes are fixed: 'inions air' is Pinion's Aria."
    UI.rodMatch := AddT("Rods", PAGE_X + 130, y + ROW_H - 4, LEFT_W - 130, 22, "", "body", 9, Pal.dim, Pal.content, "0x200")
    names := ""
    for lib in RodLib
        names .= (names = "" ? "" : ", ") lib.name
    UI.rodNote := AddT("Rods", PAGE_X, RowBase + 5 * ROW_H, LEFT_W, 60, "", "body", 9, Pal.dim, Pal.content)
    Pages["Rods"].desc := "Built-in reel styles: " names ". Other rods use the standard reel."
}

BuildLive() {
    global ColX, RowBase
    PageHead("Live", "Live view", "What FISCHXR sees in the reel.")
    UI.livePic := MainGui.Add("Picture", Format("x{} y{} w{} h{} Background000000", ZS(PAGE_X), ZS(76), ZS(LEFT_W), ZS(64)))
    Pages["Live"].ctls.Push(UI.livePic)
    UI.liveNone := AddT("Live", PAGE_X, 76, LEFT_W, 64, "Nothing to show yet. Start fishing, or press Preview with a reel on screen.", "body", 9, Pal.dim, Pal.field, "Center 0x200")
    labels := [["look", "Rod"], ["bar", "Bar"], ["fish", "Fish"], ["off", "Fish offset"], ["edges", "Reel outline"], ["cover", "Match"], ["rate", "Speed"], ["mode", "Status"]]
    cw := LEFT_W // 2
    for i, l in labels {
        c := (i - 1) // 4, r := Mod(i - 1, 4)
        x := PAGE_X + c * cw, y := 146 + r * 20
        AddT("Live", x, y, 78, 20, l[2], "body", 9, Pal.dim, Pal.content, "0x200")
        UI.liveVals[l[1]] := AddT("Live", x + 78, y, cw - 82, 20, "–", "body", 9, Pal.text, Pal.content, "0x200")
    }
    third := (LEFT_W - 16) // 3
    RowBase := 232
    UI.btnPreview := ActionBtn("Live", 0, "Preview", (*) => ToggleLivePreview(), "Shows the reel area live even when not fishing.", PAD, third)
    ActionBtn("Live", 0, "Save snapshot", (*) => SaveLiveSnapshot(), "Saves what the macro sees now, plus a report, to the Snapshots folder.", PAD + third + 8, third)
    ActionBtn("Live", 0, "Open snapshots", (*) => OpenSnapshots(), "Opens the Snapshots folder next to the macro.", PAD + 2 * (third + 8), third)
    RowBase := ROW_Y0
    AddT("Live", PAGE_X, 270, 200, 18, "Detection log", "body", 9, Pal.dim, Pal.content)
    UI.liveLog := AddT("Live", PAGE_X, 288, LEFT_W, 62, "", "body", 9, Pal.text, Pal.content)
    Pages["Live"].desc := ""
}

BuildReel() {
    PageHead("Reel", "Reel", "How the bar follows the fish.")
    Seg("Reel", 0, "ControlStyle", "Control style", [["physics", "Physics"], ["simple", "Simple"]]
        , "Physics learns how your rod's bar speeds up and slows down, then brakes so it stops on the fish. Simple predicts a fixed time ahead.")
    Stepper("Reel", 1, "Latency")
    Stepper("Reel", 2, "Braking")
    Stepper("Reel", 3, "EdgeMargin")
    Stepper("Reel", 4, "ScanDelay")
    Stepper("Reel", 5, "Predict")
    Toggle("Reel", 6, "ReelSnaps", "Record each reel's end", "Saves a screenshot, the reel band and a frame-by-frame report every time a reel ends, to Snapshots\Reels. Keeps the last 10.")
    Pages["Reel"].desc := ""
}

BuildTiming() {
    PageHead("Timing", "Timing", "Wait times.")
    for i, k in ["CastHold", "BobberWait", "BiteTimeout", "CatchDelay", "ShakeInterval", "ShakeTol", "TotemWait", "NightLevel"]
        Stepper("Timing", i - 1, k)
    Pages["Timing"].desc := ""
}

BuildMore() {
    PageHead("More", "More", "Other options.")
    Toggle("More", 0, "ColorSafe", "Color-blind safe colors", "Dark and Light themes: swaps teal, amber and coral for blue, yellow and orange.")
    Toggle("More", 1, "ReduceMotion", "Reduce motion", "Skips loading animations and slows the live gauge to a calm refresh.")
    Toggle("More", 2, "Speak", "Read status aloud", "Speaks status changes and the setting under keyboard focus with the Windows voice.")
    Toggle("More", 3, "Sounds", "Sound cues", "Plays a short sound when fishing starts, a reel finishes, or something needs attention.")
    Toggle("More", 4, "ShowSplash", "Show loading screen", "Shows the logo and startup steps while the macro opens.")
    Toggle("More", 5, "UseNavKey", "Press nav key first", "Presses the UI navigation key (\) before shaking. Only turn this on if Enter alone doesn't shake.")
    Toggle("More", 6, "HookShots", "Screenshots in alerts", "Adds a picture of the Roblox window to problem and disconnect messages.")
    UI.reset := ActionBtn("More", 7, "Reset all settings", (*) => ConfirmReset(), "Deletes FischMacro.ini, including learned rod looks, and restarts the macro.")
    Pages["More"].desc := ""
}

PageHead(page, title, intro) {
    AddT(page, PAGE_X, 12, LEFT_W - 90, 30, title, "display", 15, Pal.text, Pal.content, "0x200")
    AddT(page, PAGE_X, 44, LEFT_W, 32, intro, "body", 9, Pal.dim, Pal.content)
}

; (Kept for older page code: one column only now.)
Col(page, n, heading := "") {
    global ColX, RowBase
    ColX := PAGE_X - PAD, RowBase := ROW_Y0
}

;------------------------------------------------------------------------------
; Row controls. Each registers its clickable parts, hover help and a keyboard
; focus item (name, activate, adjust, spoken value, help text). ColX shifts a
; row into the right-hand column; RowBase is where row 0 sits.
;------------------------------------------------------------------------------
Stepper(page, row, key, swatchKey := "") {
    sp := NumSpec[key], y := RowBase + row * ROW_H, ox := ColX, lx := PAD + ox
    lab := AddT(page, lx, y, 290, 28, sp.label, "body", 10, Pal.text, Pal.content, "0x200")
    minus := AddT(page, ox + 318, y, 28, 28, "−", "body", 12, Pal.dim, Pal.field, "Center 0x200")
    val := AddT(page, ox + 348, y, 64, 28, StepText(key), "num", 11, Pal.text, Pal.field, "Center 0x200")
    plus := AddT(page, ox + 414, y, 28, 28, "+", "body", 12, Pal.dim, Pal.field, "Center 0x200")
    unit := AddT(page, ox + 446, y, 34, 28, StepUnit(key), "body", 9, Pal.dim, Pal.content, "0x200")
    UI.units[key] := unit
    Clickables[minus.Hwnd] := {kind: "step", key: key, dir: -1, obj: minus, bg: Pal.field, hv: Pal.fieldHi}
    Clickables[plus.Hwnd] := {kind: "step", key: key, dir: 1, obj: plus, bg: Pal.field, hv: Pal.fieldHi}
    Clickables[val.Hwnd] := {kind: "value", key: key, obj: val}
    Steppers[key] := val
    for c in [lab, minus, val, plus, unit]
        DescOf[c.Hwnd] := sp.help
    AddFocus(page, [minus, val, plus], sp.label, 0, StepSetting.Bind(key), SpokenValue.Bind(key), sp.help)
}

Toggle(page, row, key, label, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 340, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    t := MainGui.Add("Picture", Format("x{} y{} w{} h{}", ZS(ox + 400), ZS(y + 2), ZS(SwitchArt.W), ZS(SwitchArt.H)), "HBITMAP:*" SwitchArt.Frame(Cfg[key] ? 1 : 0))
    Pages[page].ctls.Push(t)
    SwitchPos[t.Hwnd] := Cfg[key] ? 1 : 0
    Clickables[t.Hwnd] := {kind: "toggle", key: key, obj: t}
    Toggles[key] := t
    DescOf[lab.Hwnd] := desc, DescOf[t.Hwnd] := desc
    PaintToggle(key)
    AddFocus(page, [t], label, FlipToggle.Bind(key), ToggleAdj.Bind(key), SpokenValue.Bind(key), desc)
}

KeyBtn(page, row, key, label, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 300, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    b := AddT(page, ox + 346, y, 96, 28, Cfg[key] = "" ? "Not set" : KeyName(Cfg[key]), "num", 10, Pal.text, Pal.field, "Center 0x200")
    Clickables[b.Hwnd] := {kind: "key", key: key, obj: b, bg: Pal.field, hv: Pal.fieldHi}
    KeyBtns[key] := b
    DescOf[lab.Hwnd] := desc, DescOf[b.Hwnd] := desc
    AddFocus(page, [b], label, CaptureKeyFor.Bind(key), 0, SpokenValue.Bind(key), desc " Press Enter, then the new key.")
}

Seg(page, row, key, label, options, desc) {
    y := RowBase + row * ROW_H, n := options.Length, sw := 96, ox := ColX
    x := ox + 442 - n * sw - (n - 1) * 2
    lab := AddT(page, PAD + ox, y, x - PAD - ox - 8, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    DescOf[lab.Hwnd] := desc
    SegCtls[key] := []
    ctls := []
    for o in options {
        s := AddT(page, x, y, sw, 28, o[2], "body", 9, Pal.dim, Pal.field, "Center 0x200")
        Clickables[s.Hwnd] := {kind: "seg", key: key, value: o[1], obj: s}
        SegCtls[key].Push({ctl: s, value: o[1], text: o[2]})
        DescOf[s.Hwnd] := desc
        ctls.Push(s)
        x += sw + 2
    }
    PaintSegs(key)
    AddFocus(page, ctls, label, CycleChoice.Bind(key, 1), CycleChoice.Bind(key), SpokenValue.Bind(key), desc)
}

Choice(page, row, key, label, options, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 230, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    c := AddT(page, ox + 262, y, 180, 28, "", "body", 9, Pal.text, Pal.field, "Center 0x200")
    Clickables[c.Hwnd] := {kind: "choice", key: key, obj: c, bg: Pal.field, hv: Pal.fieldHi}
    Choices[key] := {ctl: c, options: options}
    DescOf[lab.Hwnd] := desc, DescOf[c.Hwnd] := desc
    PaintChoice(key)
    AddFocus(page, [c], label, OpenChoiceMenu.Bind(key), CycleChoice.Bind(key), SpokenValue.Bind(key), desc " Arrow keys change it.")
}

ActionBtn(page, row, text, fn, desc, x := PAD, w := LEFT_W) {
    y := RowBase + row * ROW_H
    b := AddT(page, x + ColX, y, w, 30, text, "body", 10, Pal.text, Pal.field, "Center 0x200")
    Clickables[b.Hwnd] := {kind: "btn", fn: fn, obj: b, bg: Pal.field, hv: Pal.fieldHi}
    DescOf[b.Hwnd] := desc
    AddFocus(page, [b], text, fn, 0, 0, desc)
    return b
}

; A labelled one-line text field bound to a text setting.
EditRow(page, row, key, label, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 126, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    e := AddEdit(page, PAD + ox + 128, y, LEFT_W - 128, 28, Cfg[key], key)
    DescOf[lab.Hwnd] := desc
    AddFocus(page, [e], label, FocusEdit.Bind(e), 0, () => Cfg[key] = "" ? "empty" : "filled in", desc " Press Enter to type.")
    return e
}

AddEdit(page, x, y, w, h, value, key) {
    SetFontFor(MainGui, "norm s" FZ(10) " c" Pal.text, "body")
    e := MainGui.Add("Edit", Format("x{} y{} w{} h{} -E0x200 -Wrap r1 Background{}", ZS(x), ZS(y) + ZS(3), ZS(w), ZS(h) - ZS(4), Pal.field), value)
    if (page != 0)
        Pages[page].ctls.Push(e)
    EditCtls[e.Hwnd] := {key: key, ctl: e}
    if (key != "rename")
        e.OnEvent("Change", EditChanged.Bind(key))
    return e
}

Tile(page, x, y, w, h, title, sub, fn, primary := false) {
    bg := primary ? Pal.accent : Pal.field, hv := primary ? Pal.accentHi : Pal.fieldHi
    fg := primary ? Pal.ink : Pal.text, fg2 := primary ? Pal.ink : Pal.dim
    lp := AddT(page, x, y, 16, h, "", "body", 9, fg, bg)
    t := AddT(page, x + 16, y, w - 16, 40, title, "display", 12, fg, bg, "0x200")
    s := AddT(page, x + 16, y + 40, w - 16, h - 40, sub, "body", 9, fg2, bg)
    e := {kind: "btn", fn: fn, obj: t, objs: [lp, t, s], bg: bg, hv: hv}
    for c in [lp, t, s]
        Clickables[c.Hwnd] := e
    AddFocus(page, [lp, t, s], title, fn, 0, 0, sub)
    return {title: t, sub: s, entry: e}
}

AddFocus(page, ctls, name, act, adj, value, desc) {
    item := {ctls: ctls, name: name, act: act, adj: adj, value: value, desc: desc}
    Pages[page].focus.Push(item)
    return item
}

;------------------------------------------------------------------------------
; Showing, switching and laying out
;------------------------------------------------------------------------------
ShowMain(tab, px := "", py := "") {
    SwitchTab(tab, false)
    w := ZS(Cfg["WinW"]), h := ZS(Cfg["WinH"])
    MonitorGetWorkArea(, &L, &T, &R, &B)
    w := Min(w, Floor((R - L) * 96 / A_ScreenDPI)), h := Min(h, Floor((B - T) * 96 / A_ScreenDPI))
    x := px != "" ? px : Cfg["WinX"], y := py != "" ? py : Cfg["WinY"]
    pos := ""
    if (IsNumber(x) && IsNumber(y) && PointOnScreen(Integer(x) + 60, Integer(y) + 20))
        pos := Format("x{} y{} ", Integer(x), Integer(y))
    fade := !Cfg["ReduceMotion"]
    if fade
        WinSetTransparent(0, MainGui.Hwnd)
    MainGui.Show(pos "w" w " h" h)
    if fade
        FadeWindow(MainGui.Hwnd, 260)
    StyleWindow(MainGui.Hwnd)
    try ApplyAppIcon(MainGui.Hwnd)
    Layout()
    UpdateAll()
}

SwitchTab(name, speak := true) {
    global CurTab, FocusOn
    if !Pages.Has(name)
        return
    if (CurTab = "Rods" && name != "Rods")
        try CommitRename(false)
    CurTab := name
    locked := TabLocked(name)                   ; a guest sees a sign-in panel instead
    for t, pg in Pages
        for c in pg.ctls
            c.Visible := (t = name) && !locked
    LockPanel.Show(locked ? name : "")
    ; an Advanced page brings the Advanced tabs into the sidebar, and back
    mode := "basic"
    for t in AdvTabs
        if (t = name)
            mode := "adv"
    UI.navMode := mode
    UI.desc.Visible := (name != "Home")        ; hover help and messages show here
    UI.desc.Text := Pages[name].desc
    PaintTabs()
    SlideIn(Pages[name].ctls)
    switch name {
        case "Rods": RodsChanged()
        case "Sovereign": PaintSovStatus()
        case "Totems": TotemsChanged()
        case "Alerts": PaintHookStatus()
        case "Reconnect": PaintReconnectStatus()
        case "Live": LiveShow()
    }
    if (name != "Live")
        SetTimer(LiveTick, 0)
    if UiReady
        Layout()
    if FocusOn {
        FocusOn := false
        HideRing()
    }
    if (name != "Home" && Cfg["LastTab"] != name) {
        Cfg["LastTab"] := name
        Save("LastTab")
    }
    if speak
        Say(name " tab")
}

CycleTab(dir) {
    list := UI.navMode = "adv" ? AdvTabs : BasicTabs
    for i, t in list
        if (t = CurTab)
            return SwitchTab(list[Mod(i - 1 + dir + list.Length, list.Length) + 1])
    SwitchTab(list[1])
}

PaintTabs() {
    ; only the rows whose state changed are repainted (repainting all of them
    ; on every change made the sidebar slow)
    for name, row in UI.navRows {
        on := (name = CurTab), vis := (row.mode = UI.navMode), e := row.entry
        if (row.HasOwnProp("on") && row.on = on && row.vis = vis)
            continue
        row.on := on, row.vis := vis
        e.bg := on ? Pal.field : Pal.strip, e.hv := on ? Pal.field : Pal.fieldHi
        row.icon.Opt("Background" e.bg " c" (on ? Pal.text : Pal.dim))
        if (row.icon.Visible != vis)
            row.icon.Visible := vis
        if vis
            row.icon.Redraw()
    }
    MoveNavMark()
    Flyout.Paint()
}

; Slides the active tab's mark to its tab (or hides it when that tab's set
; isn't showing).
MoveNavMark() {
    if !UI.HasOwnProp("navInd")
        return
    ind := UI.navInd
    if !(UI.navRows.Has(CurTab) && UI.navRows[CurTab].mode = UI.navMode) {
        ind.Visible := false
        return
    }
    ty := ZS(UI.navRows[CurTab].y)
    ind.GetPos(, &y0)
    if (!ind.Visible || Cfg["ReduceMotion"] || !UiReady || !DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd)) {
        ind.Move(, ty), ind.Visible := true
        return
    }
    if (ty = y0)
        return
    Anim.Run(170, (e) => ind.Move(, Round(y0 + (ty - y0) * e)), "mark")
}

Layout() {
    if (!UiReady || !IsObject(MainGui))
        return
    MainGui.GetClientPos(, , &W, &H)
    UI.btnClose.Move(W - ZS(40), 0)
    UI.btnMin.Move(W - ZS(80), 0)
    UI.startBtn.Move(, H - ZS(52))
    x0 := ZS(PAGE_X), cw := Max(ZS(300), W - x0 - ZS(16))
    for c in [UI.dStatus, UI.dDetail, UI.sep1, UI.sep2, UI.evHead, UI.hRbx]
        c.Move(, , c = UI.hRbx ? cw - ZS(16) : cw)
    for c in [UI.iRod, UI.iPhys, UI.iAq, UI.iRbx]
        c.Move(, , cw - ZS(80))
    UI.mCtrL.Move(x0 + cw // 2), UI.mCtr.Move(x0 + cw // 2 + ZS(66))
    UI.events.Move(, , cw, Max(ZS(20), H - ZS(STATUS_H) - ZS(6) - ZS(322)))
    UI.desc.Move(x0, H - ZS(STATUS_H) - ZS(36), cw, ZS(34))
    UI.livePic.Move(x0, ZS(76), cw, ZS(64))
    UI.liveNone.Move(x0, ZS(76), cw, ZS(64))
    UI.liveLog.Move(, , cw, Max(ZS(20), H - ZS(STATUS_H) - ZS(40) - ZS(288)))
    UI.gX := x0, UI.gW := cw
    SetGauge(GaugeState.l, GaugeState.r, GaugeState.f, GaugeState.live)
    y := H - ZS(STATUS_H)
    for it in UI.sbLeft
        it.ctl.Move(, y + ZS(it.dy))
    for it in UI.sbRight
        it.ctl.Move(W - ZS(it.off), y + ZS(it.dy))
    if FocusOn
        try ShowFocus(FocusList()[FocusIdx], false)
    DllCall("InvalidateRect", "Ptr", MainGui.Hwnd, "Ptr", 0, "Int", 1)
}

UpdateAll() {
    PaintPhase()
    UpdateStats()
    UpdateStartControls()
    PaintChips()
    UpdateEvents()
    RefreshRobloxInfo()
}

ToggleMaximize() {
    global Maxed, NormalRect
    hwnd := MainGui.Hwnd
    if !Maxed {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        NormalRect := {x: x, y: y, w: w, h: h}
        MonitorGetWorkArea(MonitorAt(x + w // 2, y + h // 2), &L, &T, &R, &B)
        SizeWindow(hwnd, L, T, R - L, B - T)
        Maxed := true
    } else {
        SizeWindow(hwnd, NormalRect.x, NormalRect.y, NormalRect.w, NormalRect.h)
        Maxed := false
    }
    try UI.btnMax.Text := IconOr(Chr(Maxed ? 0xE923 : 0xE922), Maxed ? "❐" : "□")
    Layout()
}

; Drag-resize from the right edge, bottom edge or bottom-right corner.
ResizeLoop(zone) {
    if Maxed
        return
    hwnd := MainGui.Hwnd
    WinGetPos(, , &w0, &h0, "ahk_id " hwnd)
    MouseGetPos(&mx0, &my0)
    minW := ToPhys(MIN_W), minH := ToPhys(MIN_H), lw := w0, lh := h0
    while GetKeyState("LButton", "P") {
        MouseGetPos(&mx, &my)
        nw := InStr(zone, "r") ? Max(minW, w0 + mx - mx0) : w0
        nh := InStr(zone, "b") ? Max(minH, h0 + my - my0) : h0
        if (nw != lw || nh != lh) {
            ; WM_SETREDRAW off clears WS_VISIBLE on a top-level window, so the
            ; window is resized by handle rather than looked up by title.
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
            SizeWindow(hwnd, "", "", nw, nh)
            Layout()
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
            DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x585)
            lw := nw, lh := nh
        }
        Sleep 15
    }
    SaveGeometry()
}

; Moves and/or sizes a window by handle, in physical pixels. Blank x/y keeps the position.
SizeWindow(hwnd, x, y, w, h) {
    flags := 0x0014 | (x = "" ? 0x0002 : 0)      ; NOZORDER | NOACTIVATE [| NOMOVE]
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", x = "" ? 0 : x, "Int", y = "" ? 0 : y, "Int", w, "Int", h, "UInt", flags)
}

SaveGeometry() {
    if (!IsObject(MainGui) || !UiReady)
        return
    try {
        if (WinGetMinMax("ahk_id " MainGui.Hwnd) != 0)
            return
        if Maxed {
            Cfg["WinX"] := NormalRect.x, Cfg["WinY"] := NormalRect.y
        } else {
            MainGui.GetPos(&x, &y)
            MainGui.GetClientPos(, , &w, &h)
            Cfg["WinX"] := x, Cfg["WinY"] := y
            Cfg["WinW"] := Max(MIN_W, Round(w / Zoom)), Cfg["WinH"] := Max(MIN_H, Round(h / Zoom))
            Save("WinW"), Save("WinH")
        }
        Save("WinX"), Save("WinY")
    }
}

RebuildGui() {
    global UiReady, Zoom, FocusOn, FocusIdx, Maxed
    if !IsObject(MainGui)
        return
    SaveGeometry()
    try WinGetPos(&wx, &wy, , , "ahk_id " MainGui.Hwnd)
    if Maxed
        wx := NormalRect.x, wy := NormalRect.y, Maxed := false
    tab := CurTab, fOn := FocusOn, fIdx := FocusIdx
    UiReady := false
    Dialog.Close()
    DestroyOverlays()
    old := MainGui, oldLogo := UI.HasOwnProp("logoHbm") ? UI.logoHbm : 0
    ResolveTheme()
    Zoom := Cfg["Zoom"] / 100
    FreeBrushes()
    BuildGui()
    ShowMain(tab, IsSet(wx) ? wx : "", IsSet(wy) ? wy : "")
    try old.Destroy()
    if oldLogo
        DllCall("DeleteObject", "Ptr", oldLogo)
    if fOn {
        list := FocusList()
        if list.Length {
            FocusOn := true, FocusIdx := Min(fIdx, list.Length)
            ShowFocus(list[FocusIdx], false)
        }
    }
    if Cfg["ShowAreas"]
        UpdateOverlay()
}

;------------------------------------------------------------------------------
; Painting state onto controls
;------------------------------------------------------------------------------
; A switch slides to its new position, its track fading between grey and
; the accent colour.
PaintToggle(key) {
    if Toggles.Has(key) {
        t := Toggles[key], to := Cfg[key] ? 1 : 0
        from := SwitchPos.Has(t.Hwnd) ? SwitchPos[t.Hwnd] : 1 - to
        if (from != to)
            Anim.Run(150, SwitchStep.Bind(t, from, to), "sw" t.Hwnd)
        else
            SetSwitch(t, to)
    }
    PaintChips()
}
SwitchStep(t, from, to, e) => SetSwitch(t, from + (to - from) * e)
SetSwitch(t, pos) {
    SwitchPos[t.Hwnd] := pos
    old := SendMessage(0x172, 0, SwitchArt.Frame(pos), t.Hwnd)        ; STM_SETIMAGE
    if (old && !SwitchArt.Owns(old))
        DllCall("DeleteObject", "Ptr", old)                          ; (the control's own copy)
}

PaintChips() {
    if !UI.HasOwnProp("chips")
        return
    for key, c in UI.chips {
        on := Cfg[key]
        c.Opt("Background" (on ? Pal.field : Pal.bar))
        c.SetFont("c" (on ? Pal.accent : Pal.dim))
        c.Redraw()
    }
}

PaintSegs(key) {
    if !SegCtls.Has(key)
        return
    for s in SegCtls[key] {
        on := (Cfg[key] = s.value)
        s.ctl.Opt("Background" (on ? Pal.accent : Pal.field))
        s.ctl.SetFont(on ? "w600 c" Pal.ink : "w400 c" Pal.dim)
        s.ctl.Redraw()
    }
}

PaintChoice(key) {
    if Choices.Has(key)
        Choices[key].ctl.Text := ChoiceText(key) "  ▼"
}

ChoiceText(key) {
    if Choices.Has(key)
        for o in Choices[key].options
            if (o[1] = Cfg[key])
                return o[2]
    if SegCtls.Has(key)
        for s in SegCtls[key]
            if (s.value = Cfg[key])
                return s.text
    return Cfg[key]
}

UpdateStartControls() {
    if !UiReady
        return
    try {
        b := UI.startBtn, e := Clickables[b.Hwnd]
        busy := Running || AqManual, k := KeyName(Cfg["ToggleKey"])
        e.bg := busy ? Pal.field : Pal.accent, e.hv := busy ? Pal.fieldHi : Pal.accentHi
        b.Text := HasIconFont ? Chr(busy ? 0xE71A : 0xE768) : (busy ? "■" : "►")
        b.Opt("Background" (Hover = b.Hwnd ? e.hv : e.bg) " c" (busy ? Pal.stop : Pal.ink))
        b.Redraw()
        Flyout.PaintStart(busy, k)
        if (busy && !Cfg["ReduceMotion"])
            SetTimer(PulseDot, 70)
    }
}

PhaseColor(kind) {
    if (kind = "wait" || kind = "pause")
        return Pal.wait
    if (kind = "reel" || kind = "aqua")
        return Pal.accent
    if (kind = "error")
        return Pal.stop
    return Pal.text
}

SetPhase(kind, title, detail := "") {
    if (!Running && !AqManual && kind != "idle" && kind != "error")
        return
    changed := (title != Phase.title)
    Phase.kind := kind, Phase.title := title, Phase.detail := detail
    PaintPhase()
    if changed {
        try MainGui.Title := APP_NAME " - " title
        A_IconTip := SubStr(APP_NAME ": " title, 1, 120)
        if (title != "Casting" && title != "Waiting for a bite")
            Say(title)
        if (kind = "pause")
            Cue("pause")
    }
}

PaintPhase() {
    if !UiReady
        return
    try {
        col := PhaseColor(Phase.kind)
        changed := UI.dStatus.Text != Phase.title
        if changed
            UI.dStatus.Text := Phase.title
        if (UI.sbStatus.Text != Phase.title)
            UI.sbStatus.Text := Phase.title
        if (col != UI.phaseColor) {
            UI.dStatus.SetFont("c" col), UI.sbDot.SetFont("c" col)
            UI.phaseColor := col
        }
        if changed {
            FadeText(UI.dStatus, Pal.content, col, 280, "stfade")
            FadeText(UI.sbStatus, Pal.bar, Pal.text, 280, "sbfade")
        }
        det := (Phase.detail = "" && Phase.kind = "idle") ? IdleHint() : Phase.detail
        if (UI.dDetail.Text != det)
            UI.dDetail.Text := det
    }
    Hud.Update()
}

SetDetail(text) {
    Phase.detail := text
    if !UiReady
        return
    try {
        if (UI.dDetail.Text != text)
            UI.dDetail.Text := text
    }
}

; l, r and f are fractions of the reel track. f < 0 leaves the fish tick alone.
SetGauge(l, r, f, live) {
    GaugeState.l := l, GaugeState.r := r, GaugeState.live := live
    if (f >= 0)
        GaugeState.f := f
    Hud.Gauge(l, r, GaugeState.f, live)
    if !UiReady
        return
    try {
        w := UI.gW, x0 := UI.gX
        bl := Round(Clamp(l, 0, 1) * w), br := Round(Clamp(r, 0, 1) * w)
        if (br - bl < 2)
            br := Min(w, bl + 2), bl := br - 2
        UI.gL.Move(x0, , bl)
        UI.gBar.Move(x0 + bl, , br - bl)
        UI.gR.Move(x0 + br, , w - br)
        UI.gCtr.Move(x0 + (bl + br) // 2 - 1)
        UI.gFish.Move(x0 + Round(Clamp(GaugeState.f, 0, 1) * (w - 3)))
        if (live != UI.gLive) {
            UI.gLive := live
            UI.gBar.Opt("Background" (live ? Pal.accent : Pal.faint))
            UI.gFish.Opt("Background" (live ? Pal.text : Pal.faint))
            UI.gCtr.Opt("Background" (live ? Pal.dim : Pal.faint))
            UI.gBar.Redraw(), UI.gFish.Redraw(), UI.gCtr.Redraw()
            if !live {
                UI.mOff.Text := "–"
                UI.mCtr.Text := "–"
            }
        }
    }
}

SetLive(offset, centered) {
    if !UiReady
        return
    try {
        t1 := (offset = "") ? "–" : Format("{:+d}%", Round(offset * 100))
        t2 := (centered = "") ? "–" : Round(centered * 100) "%"
        if (UI.mOff.Text != t1)
            UI.mOff.Text := t1
        if (UI.mCtr.Text != t2)
            UI.mCtr.Text := t2
    }
}

UpdateStats() {
    if !UiReady
        return
    try {
        static lastC := -1, lastR := -1
        UI.sbCasts.Text := "Casts " Stats.casts
        UI.sbReels.Text := "Reels " Stats.reels
        if (lastC >= 0 && Stats.casts > lastC)
            FadeText(UI.sbCasts, Pal.accent, Pal.text, 700, "fcasts")
        if (lastR >= 0 && Stats.reels > lastR)
            FadeText(UI.sbReels, Pal.accent, Pal.text, 700, "freels")
        lastC := Stats.casts, lastR := Stats.reels
    }
    Hud.Update()
}

TickClock() {
    secs := (A_TickCount - Stats.start) // 1000
    if UiReady
        try {
            UI.sbTime.Text := Format("{}:{:02}:{:02}", secs // 3600, Mod(secs // 60, 60), Mod(secs, 60))
            Hud.Update()
            if (Mod(secs, 5) = 0) {
                t := NextJobText()
                if (UI.iAq.Text != t)
                    UI.iAq.Text := t
                if (CurTab = "Totems")
                    TotemsChanged()
            }
        }
}

; The soonest between-catch job, for the dashboard.
NextJobText() {
    jobs := []
    if Cfg["AqAuto"]
        jobs.Push(["Aquarium", AqNext])
    if Cfg["TotemAuto"]
        for t in Totems
            if (t.on && t.slot != "")
                jobs.Push([t.name " Totem", t.next])
    if !jobs.Length
        return Cfg["SovAuto"] ? "Sovereign recharge, every " Cfg["SovEvery"] " reels" : "None scheduled"
    if !Running
        return jobs.Length " job" (jobs.Length = 1 ? "" : "s") " scheduled"
    best := jobs[1]
    for j in jobs
        if (j[2] < best[2])
            best := j
    m := Max(0, Round((best[2] - A_TickCount) / 60000))
    return best[1] (m ? " in " m " min" : " next")
}

UpdateRodInfo(p, frac, key) {
    global RodInfoText
    RodInfoText := p.name
    if UiReady
        try {
            UI.iRod.Text := RodInfoText
            RodsChanged()
            if (CurTab = "Rods")
                RodsChanged()
            Hud.Update()
        }
}

PhysicsText(key := "") {
    if (Cfg["ControlStyle"] = "simple")
        return "Simple look-ahead, " Cfg["Predict"] " ms"
    if (Cfg["Latency"] > 0)
        lagTxt := ", " Cfg["Latency"] " ms lag (set)"
    else
        lagTxt := Cfg["LearnedLag"] > 0 ? ", " Cfg["LearnedLag"] " ms lag" : ", measuring lag"
    if (key != "" && RodMem.Has(key)) {
        n := RodMem[key].n
        return "Learned from " n " reel" (n = 1 ? "" : "s") lagTxt
    }
    return (key != "" ? "Learning this rod" : "Learns each rod") lagTxt
}

RodSegText() {
    return "Rod: " (IsObject(CurRod) ? CurRod.name : "not seen yet")
}

LogEvent(text) {
    Events.InsertAt(1, FormatTime(, "HH:mm") "   " text)
    if (Events.Length > 30)
        Events.Pop()
    UpdateEvents()
}

UpdateEvents() {
    if UiReady
        try UI.events.Text := EventsText()
}

EventsText() {
    s := ""
    for i, e in Events {
        if (i > 6)
            break
        s .= (s = "" ? "" : "`n") e
    }
    return s = "" ? "Nothing yet." : s
}

StepUnit(key) {
    t := StepText(key)
    return (t = "Auto" || t = "Off") ? "" : NumSpec[key].unit
}

;------------------------------------------------------------------------------
; Rods tab
;------------------------------------------------------------------------------
RodsTileText() {
    n := RodProfiles.Length
    if !n
        return "Learned on the first reel with each"
    return n " look" (n = 1 ? "" : "s") " learned" (IsObject(CurRod) ? ", using " CurRod.name : "")
}

RodsChanged() {
    if (!UiReady || !UI.HasOwnProp("rodName"))
        return
    UI.rodName.Text := CurRodName != "" ? CurRodName (Cfg["RodManual"] != "" ? "  (typed)" : "") : RodReadBusy ? "Reading…" : "Not read yet"
    style := "–"
    if (CurRodLib != "")
        style := RodById(CurRodLib).name
    else if IsObject(CurRod)
        style := RodById(CurRod.lib).name " (from the reel)"
    UI.rodStyle.Text := style
    UI.rodNote.Text := RodReadLast
    try UI.iPhys.Text := style
    if (CurRodName != "")
        try UI.iRod.Text := CurRodName
}





CommitRename(keep) => 0



PaintSovStatus() {
    if !UiReady
        return
    s := Cfg["SovAuto"] ? "On. Every " Cfg["SovEvery"] " reels it uses " Cfg["SovCount"] " plain Enchant Relic" (Cfg["SovCount"] = 1 ? "" : "s") " (no mutation) from your inventory." : "Off."
    if (SovLast != "")
        s .= "`nLast recharge " SovLast "."
    else if Cfg["SovAuto"]
        s .= "`nNext after " Max(0, Cfg["SovEvery"] - SovReels) " more reel" (Cfg["SovEvery"] - SovReels = 1 ? "" : "s") "."
    try UI.sovStatus.Text := s
}

Join(list, sep) {
    s := ""
    for v in list
        s .= (A_Index = 1 ? "" : sep) v
    return s
}

;------------------------------------------------------------------------------
; Totems tab
;------------------------------------------------------------------------------
TotemsChanged() {
    if (!UiReady || !UI.totemRows.Length)
        return
    on := CurTab = "Totems"
    for i, r in UI.totemRows {
        show := on && i <= Totems.Length
        for c in [r.on, r.name, r.night, r.key, r.less, r.every, r.more, r.unit, r.del]
            c.Visible := show
        if (i > Totems.Length)
            continue
        t := Totems[i]
        r.on.Text := t.on ? "On" : "Off"
        r.on.Opt("Background" (t.on ? Pal.accent : Pal.field)), r.on.SetFont(t.on ? "w600 c" Pal.ink : "w400 c" Pal.dim)
        r.name.Text := t.name
        r.name.SetFont("c" (t.on ? Pal.text : Pal.dim))
        r.night.Opt("Background" (t.night ? Pal.fieldHi : Pal.field)), r.night.SetFont("c" (t.night ? Pal.text : Pal.faint))
        r.key.Text := t.slot = "" ? "Key?" : KeyName(t.slot)
        r.key.SetFont("c" (t.slot = "" ? Pal.wait : Pal.text))
        r.every.Text := t.every
        for c in [r.on, r.name, r.night, r.key, r.every]
            c.Redraw()
    }
    full := Totems.Length >= TOTEM_MAX
    UI.btnAddTotem.Text := full ? "Six totems scheduled" : "+  Add a totem"
    UI.btnAddTotem.SetFont("c" (full ? Pal.faint : Pal.text)), UI.btnAddTotem.Redraw()
    noKey := 0
    for t in Totems
        noKey += (t.slot = "")
    msg := !Totems.Length ? "Nothing scheduled. Add the totems you own." : noKey ? "Set the hotbar key for each totem, or it is skipped." : TotemNextText()
    Pages["Totems"].desc := msg
    if (CurTab = "Totems")
        UI.desc.Text := msg
}

TotemNextText() {
    if !Cfg["TotemAuto"]
        return "Totems are off. Turn on 'Use totems while fishing' to run the schedule."
    if !Running
        return "Each totem is used shortly after fishing starts, then on its schedule."
    s := ""
    for t in Totems
        if (t.on && t.slot != "")
            s .= (s = "" ? "Next: " : ", ") t.name " in " Max(0, Round((t.next - A_TickCount) / 60000)) " min"
    return s = "" ? "No totem has a key set." : s
}

TotemOp(op, i, *) {
    if (i > Totems.Length)
        return
    t := Totems[i]
    switch op {
        case "on": t.on := !t.on
        case "night": t.night := !t.night
        case "less": t.every := Max(1, t.every - 1)
        case "more": t.every := Min(240, t.every + 1)
        case "del": return RemoveTotem(i)
        case "name": return SetTimer(OpenTotemMenu.Bind(i), -1)
        case "key": return SetTimer(CaptureKeyFor.Bind("Totem:" i), -1)
    }
    SaveTotems()
    TotemsChanged()
}

TotemAdj(i, dir, *) => TotemOp(dir > 0 ? "more" : "less", i)
TotemSpoken(i, *) => i <= Totems.Length ? Totems[i].name ", " (Totems[i].on ? "on" : "off") ", every " Totems[i].every " minutes" : "empty"

; Menu of totem names: adds one (i = 0) or changes row i.
OpenTotemMenu(i, *) {
    global MenuOpen
    if (MenuOpen || (!i && Totems.Length >= TOTEM_MAX))
        return
    m := Menu()
    for p in TotemPresets
        m.Add(p[1] " Totem", TotemPicked.Bind(i, p[1], p[2]))
    WinGetPos(&x, &y, &w, &h, "ahk_id " (i ? UI.totemRows[i].name.Hwnd : UI.btnAddTotem.Hwnd))
    MenuOpen := true
    try m.Show(x, y + h)
    MenuOpen := false
}

TotemPicked(i, name, night, *) {
    if !i
        return AddTotem(name)
    Totems[i].name := name, Totems[i].night := night
    SaveTotems()
    TotemsChanged()
}

;------------------------------------------------------------------------------
; Alerts tab
;------------------------------------------------------------------------------
EditChanged(key, ctl, *) {
    if (key = "rodtype")                        ; the typed rod: a suggestion as you type
        return SetTimer(RodSuggest, -250)
    v := Trim(ctl.Value)
    if (Cfg[key] = v)
        return
    Cfg[key] := v
    Save(key)
    if (key = "HookUrl")
        PaintHookStatus()
}

FocusEdit(e, *) {
    e.Focus()
    SendMessage(0xB1, 0, -1, e)
}

PaintHookStatus() {
    if !UiReady
        return
    u := Cfg["HookUrl"]
    s := HookLast != "" ? HookLast : u = "" ? "No webhook link yet." : HookUrlOk(u) ? "Link looks right." : "That isn't a Discord webhook link."
    try UI.hookStatus.Text := s
}

PaintReconnectStatus() {
    if !UiReady
        return
    try UI.recStatus.Text := ReconnectStatusText()
}

;------------------------------------------------------------------------------
; Live tab: what the macro sees, redrawn a few times a second while open.
;------------------------------------------------------------------------------
LiveShow() {
    LiveLogChanged()
    LiveTick()
    SetTimer(LiveTick, (Running || LivePreview) ? 150 : 1000)
}

ToggleLivePreview() {
    global LivePreview
    LivePreview := !LivePreview
    UI.btnPreview.Text := LivePreview ? "Stop preview" : "Preview"
    SetTimer(LiveTick, LivePreview ? 150 : 1000)
    LiveTick()
}

; The frame to show: the macro's own while fishing, else a fresh grab of the
; reel area when previewing. Returns {b, d, p, ep, mode} or 0.
LiveSource() {
    global PreviewBand, PreviewGeo
    if (Running && IsObject(LiveBand)) {
        reeling := LiveT && A_TickCount - LiveT < 400
        return {b: LiveBand, d: reeling ? LiveD : 0, p: reeling ? LiveP : CurRod, ep: reeling ? LiveEp : -2
            , mode: reeling ? "Reeling" : Phase.title}
    }
    if !LivePreview
        return 0
    h := (RobloxHwnd && WinExist("ahk_id " RobloxHwnd)) ? RobloxHwnd : FindRoblox()
    cr := h ? ClientRect(h) : 0
    if !cr
        return 0
    geo := VisionGeo(AreaRect("Reel", cr))
    if (!IsObject(PreviewBand) || PreviewBand.w != geo.w || PreviewBand.h != geo.h)
        PreviewBand := BandGrab(geo.w, geo.h)
    PreviewGeo := geo
    VisionGrab(PreviewBand, geo)
    p := IsObject(CurRod) ? CurRod : (RodProfiles.Length ? RodProfiles[1] : 0)
    d := p ? VisionScan(PreviewBand, p) : 0
    return {b: PreviewBand, d: d, p: p, ep: p ? EdgesPresent(PreviewBand, geo, p) : -2
        , mode: "Preview" (p ? ", read with " p.name : ", no look learned yet")}
}

LiveTick() {
    global LiveHbm
    if (!UiReady || CurTab != "Live") {
        SetTimer(LiveTick, 0)
        return
    }
    src := LiveSource()
    UI.liveNone.Visible := !src
    UI.livePic.Visible := !!src
    V := UI.liveVals
    if !src {
        for k, c in V
            c.Text := "–"
        V["mode"].Text := Running ? Phase.title : "Idle. Press Preview to watch the reel area."
        return
    }
    b := src.b, d := src.d, p := src.p
    UI.livePic.GetPos(, , &pw, &ph)
    hbm := VisionPicture(b, d, pw, ph, Pal.HasOwnProp("mono"))
    old := LiveHbm, LiveHbm := hbm
    UI.livePic.Value := "HBITMAP:*" hbm
    if old
        DllCall("DeleteObject", "Ptr", old)
    V["look"].Text := IsObject(p) ? p.name (p.sovereign ? "  ·  Sovereign" : "") : "none learned yet"
    V["bar"].Text := (d && d.bar) ? Format("found, {}% of the track", Round(100 * (d.br - d.bl + 1) / b.w)) : d ? "not found" : "–"
    V["fish"].Text := (d && d.fish) ? (d.fishCol ? "found" : "found by contrast") : d ? "not found" : "–"
    V["off"].Text := (d && d.bar && d.fish) ? Format("{:+d}% of half the bar", Round(100 * (d.fx - (d.bl + d.br) / 2) / Max(1, (d.br - d.bl) / 2))) : "–"
    V["edges"].Text := src.ep = 1 ? "outline found" : src.ep = 0 ? "outline missing" : src.ep = -1 ? "not learned yet" : "–"
    V["cover"].Text := d ? Round(d.cover * 100) "%" : "–"
    V["rate"].Text := (Running && LiveRate) ? LiveRate " scans a second" : "–"
    V["mode"].Text := src.mode
}

LiveLogChanged() {
    if (!UiReady || CurTab != "Live")
        return
    s := ""
    for i, l in VisionLog {
        if (i > 4)
            break
        s .= (s = "" ? "" : "`n") l
    }
    try UI.liveLog.Text := s = "" ? "Nothing yet. New looks, relearning and ended reels are noted here." : s
}

; Saves the raw reel band, the annotated view and a text report.
SaveLiveSnapshot() {
    src := LiveSource()
    if !src
        return SetDetail("Nothing to save. Start fishing, or turn on Preview with the reel on screen.")
    b := src.b, d := src.d, p := src.p
    dir := A_ScriptDir "\Snapshots"
    try DirCreate(dir)
    stamp := FormatTime(, "yyyy-MM-dd_HH-mm-ss")
    DllCall("SelectObject", "Ptr", b.dc, "Ptr", b.old)
    ok := SavePng(b.bmp, dir "\" stamp "_band.png")
    DllCall("SelectObject", "Ptr", b.dc, "Ptr", b.bmp)
    hbm := VisionPicture(b, d, Max(200, b.w), Max(60, b.h * 2 + 14), false)
    SavePng(hbm, dir "\" stamp "_view.png")
    DllCall("DeleteObject", "Ptr", hbm)
    r := APP_NAME " " APP_VER " snapshot " stamp "`n`n"
    r .= "Mode: " src.mode "`nBand: " b.w " x " b.h " px`nReel box: " Format("{:.4f} {:.4f} {:.4f} {:.4f}", Cfg["ReelX1"], Cfg["ReelY1"], Cfg["ReelX2"], Cfg["ReelY2"]) "`n"
    if IsObject(p)
        r .= "`nLook: " p.name " (" p.id ")" (p.lib != "" ? ", library " p.lib : "") "`nBar width: " p.barW "`nTrack: " HexJoin(p.track) "`nBar: " HexJoin(p.bar) "`nFish: " HexJoin(p.fish) "`nEdges: " p.edgeT " / " p.edgeB "`nReels: " p.reels "`n"
    if IsObject(d)
        r .= "`nScan: bar " d.bar " (" d.bl "-" d.br "), fish " d.fish " (" Round(d.fx) (d.fishCol ? ", by colour" : ", by contrast") "), colours fit " Round(d.cover * 100) "%`n"
    r .= "`nLooks known: " RodProfiles.Length "`n`nDetection log:`n"
    for l in VisionLog
        r .= "  " l "`n"
    try FileAppend(r, dir "\" stamp "_report.txt", "UTF-8")
    SetDetail(ok ? "Saved snapshot " stamp " to the Snapshots folder." : "Couldn't save the snapshot picture.")
    LogVision("Snapshot saved: " stamp)
}

OpenSnapshots() {
    dir := A_ScriptDir "\Snapshots"
    try DirCreate(dir)
    try Run(dir)
}

;------------------------------------------------------------------------------
; The small panel in the top-right corner while fishing: what's happening,
; a mini gauge, catches, time and the rod, and a Stop button. It never takes
; focus from Roblox (WS_EX_NOACTIVATE) and can be dragged anywhere.
;------------------------------------------------------------------------------
class Hud {
    static g := 0, t := 0, d := 0, s := 0, stop := 0, gF := 0, gL := 0, gB := 0, gR := 0, W := 284, gw := 256, lastG := 0, live := -1
    static Build() {
        g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000", APP_NAME " panel")
        g.BackColor := Pal.strip
        g.MarginX := 0, g.MarginY := 0
        A(x, y, w, h, text, role, size, color, bg, extra := "") {
            SetFontFor(g, "norm s" FZ(size) " c" color, role)
            return g.Add("Text", Format("x{} y{} w{} h{} Background{} {}", ZS(x), ZS(y), ZS(w), ZS(h), bg, extra), text)
        }
        W := this.W
        A(0, 0, 3, 112, "", "body", 9, Pal.text, Pal.accent)
        A(14, 8, 150, 16, "FISCHXR", "body", 8, Pal.dim, Pal.strip, "0x200")
        this.stop := A(W - 84, 6, 74, 22, "■  Stop", "body", 9, Pal.text, Pal.field, "Center 0x200")
        this.t := A(14, 26, W - 24, 24, "", "display", 12, Pal.text, Pal.strip, "0x200 0x4000")
        this.d := A(14, 50, W - 24, 18, "", "body", 9, Pal.dim, Pal.strip, "0x200 0x4000")
        this.gF := A(14, 70, 3, 4, "", "body", 9, Pal.text, Pal.faint)
        this.gL := A(14, 75, 10, 8, "", "body", 9, Pal.text, Pal.field)
        this.gB := A(24, 75, 10, 8, "", "body", 9, Pal.text, Pal.faint)
        this.gR := A(34, 75, 10, 8, "", "body", 9, Pal.text, Pal.field)
        this.s := A(14, 88, W - 24, 18, "", "body", 9, Pal.dim, Pal.strip, "0x200 0x4000")
        this.g := g, this.live := -1
        g.Show(Format("w{} h{} Hide", ZS(W), ZS(112)))
    }
    static Show() {
        if (this.g && this.g.BackColor != Pal.strip)
            this.Destroy()                     ; the theme changed
        if !this.g
            this.Build()
        this.Update()
        MonitorGetWorkArea(HudMonitor(), &L, &T, &R, &B)
        pw := Round(ZS(this.W) * A_ScreenDPI / 96)
        x := R - pw - 16, y := T + Round((B - T) * 0.06)
        if Cfg["ReduceMotion"] {
            this.g.Show(Format("x{} y{} NoActivate", x, y))
            return
        }
        hw := this.g.Hwnd
        WinSetTransparent(0, hw)
        this.g.Show(Format("x{} y{} NoActivate", x + 60, y))    ; glides in from the edge
        glide(e) {
            try WinMove(x + Round(60 * (1 - e)), y, , , "ahk_id " hw)
            try WinSetTransparent(Round(255 * e), hw)
        }
        Anim.Run(260, glide, "hud", OpaqueAgain.Bind(hw))
    }
    static Hide() {
        if this.g
            this.g.Hide()
    }
    static Destroy() {
        if this.g
            try this.g.Destroy()
        this.g := 0
    }
    static Visible() => this.g && DllCall("IsWindowVisible", "Ptr", this.g.Hwnd)
    static Update() {
        if !this.Visible()
            return
        try {
            this.t.Text := Phase.title
            this.t.SetFont("c" PhaseColor(Phase.kind))
            this.d.Text := Phase.detail
            secs := Stats.start ? (A_TickCount - Stats.start) // 1000 : 0
            this.s.Text := Format("{} casts  ·  {} reels  ·  {}:{:02}:{:02}{}", Stats.casts, Stats.reels
                , secs // 3600, Mod(secs // 60, 60), Mod(secs, 60), IsObject(CurRod) ? "  ·  " CurRod.name : "")
        }
    }
    static Gauge(l, r, f, live) {
        if (!this.Visible() || A_TickCount - this.lastG < 80)
            return
        this.lastG := A_TickCount
        try {
            w := ZS(this.gw), x0 := ZS(14)
            bl := Round(Clamp(l, 0, 1) * w), br := Round(Clamp(r, 0, 1) * w)
            if (br - bl < 2)
                br := Min(w, bl + 2), bl := br - 2
            this.gL.Move(x0, , bl), this.gB.Move(x0 + bl, , br - bl), this.gR.Move(x0 + br, , w - br)
            this.gF.Move(x0 + Round(Clamp(f, 0, 1) * (w - 3)))
            if (live != this.live) {
                this.live := live
                this.gB.Opt("Background" (live ? Pal.accent : Pal.faint)), this.gF.Opt("Background" (live ? Pal.text : Pal.faint))
                this.gB.Redraw(), this.gF.Redraw()
            }
        }
    }
    ; Where the panel is on screen (for checks that must look past it), or 0.
    static Rect() {
        if !this.Visible()
            return 0
        WinGetPos(&x, &y, &w, &h, "ahk_id " this.g.Hwnd)
        return {x: x, y: y, w: w, h: h}
    }
}

; The monitor Roblox is on, else the primary one.
HudMonitor() {
    try {
        if (RobloxHwnd && WinExist("ahk_id " RobloxHwnd)) {
            WinGetPos(&x, &y, &w, &h, "ahk_id " RobloxHwnd)
            cx := x + w // 2, cy := y + h // 2
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &l, &t, &r, &b)
                if (cx >= l && cx < r && cy >= t && cy < b)
                    return A_Index
            }
        }
    }
    return MonitorGetPrimary()
}

; Fishing started: swap the window for the small panel (if that's on).
HudEnter() {
    if !Cfg["MiniHud"]
        return
    Hud.Show()
    if (UiReady && IsObject(MainGui) && DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd)) {
        SaveGeometry()
        MainGui.Hide()
        UI.hiddenForHud := true
    }
}

; Fishing stopped: the panel goes, the window comes back.
HudLeave() {
    Hud.Hide()
    if (UiReady && IsObject(MainGui) && UI.hiddenForHud) {
        UI.hiddenForHud := false
        if !Cfg["ReduceMotion"]
            WinSetTransparent(0, MainGui.Hwnd)
        MainGui.Show()
        if !Cfg["ReduceMotion"]
            FadeWindow(MainGui.Hwnd, 220)
        Layout()
    }
}

SelectRod(i, *) => 0

; A short slide as a page appears: its controls ease in from the right.
; Skipped with Reduce motion, and before the window is on screen.
SlideIn(ctls) {
    if (Cfg["ReduceMotion"] || !UiReady || !IsObject(MainGui) || !DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd))
        return
    Anim.Finish("slide")                     ; (a slide still running ends where it belongs first)
    pos := [], rc := Buffer(16)
    for c in ctls {
        DllCall("GetWindowRect", "Ptr", c.Hwnd, "Ptr", rc)
        DllCall("MapWindowPoints", "Ptr", 0, "Ptr", MainGui.Hwnd, "Ptr", rc, "UInt", 2)
        pos.Push([c.Hwnd, NumGet(rc, 0, "Int"), NumGet(rc, 4, "Int")])
    }
    Anim.Run(200, SlideStep.Bind(pos, ToPhys(22)), "slide", SlideDone)
    try FadeText(UI.desc, Pal.content, Pal.dim, 260, "descfade")
}
; Each step places the controls without Windows copying their old pixels
; (copied pixels left text shifted inside its box and old edges behind).
SlideStep(pos, dx, e) {
    k := Round(dx * (1 - e))
    for it in pos
        DllCall("SetWindowPos", "Ptr", it[1], "Ptr", 0, "Int", it[2] + k, "Int", it[3], "Int", 0, "Int", 0, "UInt", 0x115)   ; no size, no z-order, no activate, no copied bits
}
SlideDone() {
    try DllCall("RedrawWindow", "Ptr", MainGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x585)
}


;==============================================================================
; The full sidebar, opened over the page while the mouse is on the icon strip:
; a borderless window of its own (so it lies cleanly over the page) that slides
; open and shut. It mirrors the strip: the same tabs, the active one marked,
; and the start button with its label.
;==============================================================================
class Flyout {
    static g := 0, rows := Map(), start := 0, ind := 0, isOpen := false, away := 0, watcher := 0, placed := "", acct := 0

    static Build() {
        if this.g
            try this.g.Destroy()
        this.rows := Map(), this.isOpen := false, this.placed := ""
        g := Gui("-Caption +ToolWindow +Owner" MainGui.Hwnd (Cfg["OnTop"] ? " +AlwaysOnTop" : ""))
        g.BackColor := Pal.strip, g.MarginX := 0, g.MarginY := 0
        W := SIDEBAR_X, x := 14
        if UI.logoHbm
            g.Add("Picture", Format("x{} y{} w{} h{}", ZS((SIDEBAR_W - 24) // 2), ZS(15), ZS(24), ZS(24)), "HBITMAP:*" UI.logoHbm), x := SIDEBAR_W
        SetFontFor(g, "norm s" FZ(12) " c" Pal.text, "display")
        g.Add("Text", Format("x{} y{} w{} h{} 0x200 Background{}", ZS(x), ZS(8), ZS(W - x - 6), ZS(24), Pal.strip), "FISCHXR")
        ; who's signed in, under the name: click to sign in or out
        SetFontFor(g, "norm s" FZ(8) " c" Pal.dim, "body")
        this.acct := g.Add("Text", Format("x{} y{} w{} h{} 0x200 Background{}", ZS(x), ZS(31), ZS(W - x - 6), ZS(17), Pal.strip), "")
        Clickables[this.acct.Hwnd] := {kind: "btn", fn: (*) => AccountClick(), obj: this.acct, bg: Pal.strip, hv: Pal.fieldHi}
        PaintAccount()
        for name, row in UI.navRows {
            h := NAV_H - 4
            SetFontFor(g, "norm s" FZ(10) " c" Pal.dim, HasIconFont ? "icon" : "body")
            ic := g.Add("Text", Format("x{} y{} w{} h{} Center 0x200 Background{}", ZS(8), ZS(row.y), ZS(SIDEBAR_W - 16), ZS(h), Pal.strip), row.glyph)
            SetFontFor(g, "norm s" FZ(10) " c" Pal.dim, "body")
            lb := g.Add("Text", Format("x{} y{} w{} h{} 0x200 Background{}", ZS(SIDEBAR_W - 8), ZS(row.y), ZS(W - SIDEBAR_W), ZS(h), Pal.strip), row.label)
            e := {kind: "tab", name: name, obj: lb, objs: [ic, lb], bg: Pal.strip, hv: Pal.fieldHi}
            Clickables[ic.Hwnd] := e, Clickables[lb.Hwnd] := e
            this.rows[name] := {icon: ic, label: lb, entry: e, mode: row.mode, y: row.y}
        }
        this.ind := g.Add("Text", Format("x{} y{} w{} h{} Background{}", ZS(3), ZS(56), ZS(3), ZS(NAV_H - 4), Pal.accent))
        SetFontFor(g, "norm s" FZ(10) " c" Pal.ink, "body")
        this.start := g.Add("Text", Format("x{} y{} w{} h{} Center 0x200 Background{}", ZS(12), ZS(364), ZS(W - 24), ZS(36), Pal.accent), "")
        Clickables[this.start.Hwnd] := {kind: "btn", fn: (*) => ToggleMacro(), obj: this.start, bg: Pal.accent, hv: Pal.accentHi}
        g.Show(Format("Hide w{} h{}", ZS(W), ZS(416)))       ; (sized, and kept hidden until the strip is hovered)
        StyleWindow(g.Hwnd)                                  ; rounded, with the system's shadow
        this.g := g
        this.Paint()
    }

    static Paint() {
        if !this.g
            return
        for name, r in this.rows {
            on := (name = CurTab), e := r.entry, vis := (r.mode = UI.navMode)
            if (r.HasOwnProp("on") && r.on = on && r.vis = vis)
                continue
            r.on := on, r.vis := vis
            e.bg := on ? Pal.field : Pal.strip, e.hv := on ? Pal.field : Pal.fieldHi
            for c in [r.icon, r.label] {
                c.Opt("Background" e.bg " c" (on ? Pal.text : Pal.dim))
                if (c.Visible != vis)
                    c.Visible := vis
                if vis
                    c.Redraw()
            }
        }
        if (this.rows.Has(CurTab) && this.rows[CurTab].mode = UI.navMode)
            this.ind.Move(, ZS(this.rows[CurTab].y)), this.ind.Visible := true
        else
            this.ind.Visible := false
    }

    static PaintStart(busy, key) {
        if !this.start
            return
        e := Clickables[this.start.Hwnd]
        e.bg := busy ? Pal.field : Pal.accent, e.hv := busy ? Pal.fieldHi : Pal.accentHi
        this.start.Text := (busy ? "■  Stop" : "►  Start") "  " key
        this.start.Opt("Background" e.bg " c" (busy ? Pal.stop : Pal.ink))
        this.start.Redraw()
    }

    ; Opens over the page, from the strip's width to the full width.
    static Open() {
        if (this.isOpen || !this.g || !UiReady || !DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd))
            return
        this.isOpen := true, this.away := 0
        pt := Buffer(8, 0), rc := Buffer(16, 0)
        DllCall("ClientToScreen", "Ptr", MainGui.Hwnd, "Ptr", pt)
        DllCall("GetClientRect", "Ptr", MainGui.Hwnd, "Ptr", rc)
        cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int"), ch := NumGet(rc, 12, "Int")
        ; the start button sits at the bottom, as in the strip
        UI.startBtn.GetPos(, &sy)
        this.start.GetPos(, &fy)
        if (fy != sy)
            this.start.Move(, sy)
        ; It opens at full size and is revealed from the strip outward through
        ; a widening clip, which only paints the newly shown part (resizing it
        ; step by step redrew every control each step, which was slow).
        full := ToPhys(SIDEBAR_X), from := ToPhys(SIDEBAR_W)
        ; placing it is the slow part: only when the main window has moved
        ; or changed size since last time
        spot := cx "," cy "," ch
        if (spot != this.placed)
            WinMove(cx, cy, full, ch, this.g.Hwnd), this.placed := spot
        if Cfg["ReduceMotion"] {
            this.g.Show("NA")
        } else {
            this.Clip(from, ch)
            this.g.Show("NA")
            this.Reveal(ch, false)
        }
        if !this.watcher
            this.watcher := ObjBindMethod(this, "Watch")
        SetTimer(this.watcher, 60)
    }

    ; Shuts once the mouse has left it (and the strip) for a moment.
    static Watch() {
        if !this.isOpen
            return SetTimer(this.watcher, 0)
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int")
        WinGetPos(&fx, &fy, &fw, &fh, this.g.Hwnd)
        if (mx >= fx && mx < fx + fw && my >= fy && my < fy + fh) {
            this.away := 0
            return
        }
        if (++this.away >= 3)
            this.Close()
    }

    static Close() {
        if !this.isOpen
            return
        this.isOpen := false
        SetTimer(this.watcher, 0)
        if Cfg["ReduceMotion"] {
            this.g.Hide()
            return
        }
        WinGetPos(, , , &fh, this.g.Hwnd)
        this.Reveal(fh, true)
    }

    ; Reveals it from the strip outward (or shuts it), eased.
    static Reveal(h, closing) {
        ; (nested functions don't share the method's `this`: the class is named)
        full := ToPhys(SIDEBAR_X), edge := ToPhys(SIDEBAR_W), g := this.g
        step(e) => Flyout.Clip(Round(edge + (full - edge) * (closing ? 1 - e : e)), h)
        finish() {
            if closing {
                if !Flyout.isOpen
                    try g.Hide()
                try DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", 0, "Int", false)
            } else
                try DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", 0, "Int", true)
        }
        Anim.Run(closing ? 120 : 170, step, "fly", finish)
    }

    ; Steps the reveal (or the shutting) on a timer: each step is one clip.
    static Animate(steps, h, closing) {
        static st := 0
        if st
            SetTimer(st, 0)
        full := ToPhys(SIDEBAR_X), edge := ToPhys(SIDEBAR_W), i := 0, g := this.g
        step() {
            i++
            if (i <= steps.Length) {
                try this.Clip(Round(edge + (full - edge) * steps[i]), h)
                return
            }
            SetTimer(st, 0), st := 0
            if closing {
                if !this.isOpen                       ; (not reopened meanwhile)
                    try g.Hide()
                try DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", 0, "Int", false)
            } else
                try DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", 0, "Int", true)
        }
        st := step
        SetTimer(st, 12)
    }

    ; Shows only the left w pixels of the opened sidebar.
    static Clip(w, h) {
        DllCall("SetWindowRgn", "Ptr", this.g.Hwnd, "Ptr", DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr"), "Int", true)
    }
}

; While fishing, the status dot breathes gently.
PulseDot() {
    if (!(Running || AqManual) || Cfg["ReduceMotion"] || !UiReady) {
        SetTimer(PulseDot, 0)
        try UI.sbDot.Opt("c" UI.phaseColor), UI.sbDot.Redraw()
        return
    }
    SetTimer(PulseDot, 70)
    k := 0.5 + 0.5 * Sin(A_TickCount / 1000 * 3.9)            ; a breath about every 1.6 s
    try UI.sbDot.Opt("c" Mix(Pal.dim, Pal.accent, k)), UI.sbDot.Redraw()
}

; Opens the full sidebar once the mouse has rested on the icon strip for a
; moment (not when it only passes over it).
FlyoutIntent() {
    if (!UiReady || FocusOn)
        return
    pt := CursorClient()
    if (pt.x >= 0 && pt.x < ToPhys(SIDEBAR_W) && pt.y > ToPhys(46))
        Flyout.Open()
}


;==============================================================================
; Animation. Everything that moves goes through here: one timer steps every
; running animation, eased, so nothing ever makes the window wait. While
; something moves, Windows' timer runs at 1 ms so the steps land every ~15 ms.
;==============================================================================
class Anim {
    static items := [], ticker := 0, fine := false

    ; Calls fn(e) with e rising from 0 to 1 (eased) over ms, then done().
    ; A new animation with the same key ends the old one where it belongs.
    static Run(ms, fn, key := "", done := 0) {
        if Cfg["ReduceMotion"] {
            try fn(1.0)
            if done
                try done()
            return
        }
        if (key != "")
            this.Finish(key)
        this.items.Push({t0: A_TickCount, ms: ms, fn: fn, key: key, done: done})
        if !this.ticker
            this.ticker := ObjBindMethod(this, "Step")
        if !this.fine
            DllCall("winmm\timeBeginPeriod", "UInt", 1), this.fine := true
        SetTimer(this.ticker, 15)
    }

    ; Ends a running animation at once, at its end state.
    ; (A function kept in a property is called through a variable: called as
    ; it.fn(), AutoHotkey would pass `it` along as an extra first argument.)
    static Finish(key) {
        for i, it in this.items
            if (it.key = key) {
                this.items.RemoveAt(i)
                f := it.fn, d := it.done
                try f(1.0)
                if d
                    try d()
                return
            }
    }

    static Step() {
        cur := this.items, this.items := [], now := A_TickCount, fin := []
        for it in cur {
            p := Min(1, (now - it.t0) / it.ms), f := it.fn
            try f(1 - (1 - p) ** 3)                              ; ease out
            (p < 1) ? this.items.Push(it) : fin.Push(it)
        }
        for it in fin
            if (d := it.done)
                try d()
        if !this.items.Length {
            SetTimer(this.ticker, 0)
            if this.fine
                DllCall("winmm\timeEndPeriod", "UInt", 1), this.fine := false
        }
    }
}

; A colour between a and b ("RRGGBB"), t from 0 to 1.
Mix(a, b, t) {
    a := Integer("0x" a), b := Integer("0x" b), t := Max(0, Min(1, t))
    r := Round(((a >> 16) & 255) + ((((b >> 16) & 255) - ((a >> 16) & 255)) * t))
    g := Round(((a >> 8) & 255) + ((((b >> 8) & 255) - ((a >> 8) & 255)) * t))
    bl := Round((a & 255) + (((b & 255) - (a & 255)) * t))
    return Format("{:02X}{:02X}{:02X}", r, g, bl)
}

; A control's text colour fades from one colour to another.
FadeText(ctl, from, to, ms, key) => Anim.Run(ms, TextStep.Bind(ctl, from, to), key)
TextStep(ctl, from, to, e) {
    ctl.Opt("c" Mix(from, to, e))
    ctl.Redraw()
}

; A control's background fades from one colour to another.
FadeBack(ctl, from, to, ms, key) => Anim.Run(ms, BackStep.Bind(ctl, from, to), key)
BackStep(ctl, from, to, e) {
    ctl.Opt("Background" Mix(from, to, e))
    ctl.Redraw()
}

; A window fades in, then drops its transparency.
FadeWindow(hwnd, ms) {
    step(e) => WinSetTransparent(Round(255 * e), hwnd)
    Anim.Run(ms, step, "win" hwnd, OpaqueAgain.Bind(hwnd))
}
; Once a window stops being see-through Windows needs it repainted in full,
; or it can be left blank.
OpaqueAgain(hwnd) {
    try WinSetTransparent("Off", hwnd)
    try DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x585)
}

;==============================================================================
; The on/off switch: a rounded track and a round knob with a soft shadow,
; drawn once per theme in eight steps from off to on (the track's colour
; blending from grey to the accent colour as the knob crosses).
;==============================================================================
class SwitchArt {
    static W := 42, H := 24, N := 8, frames := [], owned := Map()

    static Build() {
        for h in this.frames
            DllCall("DeleteObject", "Ptr", h)
        this.frames := [], this.owned := Map()
        if !Gdip.Start()
            return
        w := ToPhys(this.W), h := ToPhys(this.H)
        loop this.N {
            f := this.Draw(w, h, (A_Index - 1) / (this.N - 1))
            this.frames.Push(f), this.owned[f] := true
        }
    }
    static Frame(pos) => this.frames.Length ? this.frames[1 + Round(Max(0, Min(1, pos)) * (this.N - 1))] : 0
    static Owns(h) => this.owned.Has(h)

    static Draw(w, h, p) {
        bg := Pal.content
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &g := 0)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0xFF000000 | Integer("0x" bg))
        edge := Max(1, h * 0.04), th := h - 2 * edge, r := th / 2
        ; the track, a pill
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", edge, "Float", edge, "Float", th, "Float", th, "Float", 90, "Float", 180)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", w - edge - th, "Float", edge, "Float", th, "Float", th, "Float", 270, "Float", 180)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" Mix(Pal.fieldHi, Pal.accent, p)), "Ptr*", &br := 0)
        DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", br, "Ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br), DllCall("gdiplus\GdipDeletePath", "Ptr", path)
        ; the knob, with a soft shadow under it
        d := th - 2 * Max(2, h * 0.12), kx := edge + (th - d) / 2 + p * (w - 2 * edge - th), ky := edge + (th - d) / 2
        for sh in [[1.6, 0x30000000], [0.8, 0x28000000]] {
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", sh[2], "Ptr*", &br := 0)
            DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", br, "Float", kx - sh[1] / 2, "Float", ky + sh[1], "Float", d + sh[1], "Float", d + sh[1] / 2)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
        }
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" Mix(Pal.dim, Pal.ink, p)), "Ptr*", &br := 0)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", br, "Float", kx, "Float", ky, "Float", d, "Float", d)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bmp, "Ptr*", &hbm := 0, "UInt", 0xFF000000 | Integer("0x" bg))
        DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
        return hbm
    }
}


;==============================================================================
; Settings actions
;==============================================================================
StepSetting(key, dir, mult := 1, *) {
    if (key = "Zoom")
        return ZoomStep(dir)
    sp := NumSpec[key]
    v := Clamp(Cfg[key] + dir * sp.step * mult, sp.min, sp.max)
    if (v = Cfg[key])
        return
    Cfg[key] := v
    try Steppers[key].Text := StepText(key)
    try UI.units[key].Text := StepUnit(key)
    Save(key)
    switch key {
        case "AqEvery": RefreshRobloxInfo()
        case "Predict", "Latency": RodsChanged()
        case "NightLevel", "TotemWait": TotemsChanged()
        case "SovEvery", "SovCount": PaintSovStatus()
        case "HookSummary":
            if Running
                SetTimer(SummaryTick, v ? v * 60000 : 0)
    }
}

RepeatStep() {
    if (!GetKeyState("LButton", "P") || ChildAtCursor() != Repeat.hwnd)
        return
    Repeat.n++
    StepSetting(Repeat.key, Repeat.dir, Repeat.n > 10 ? 5 : 1)
    SetTimer(RepeatStep, -60)
}

FlipToggle(key, *) {
    SetToggle(key, !Cfg[key])
}

ToggleAdj(key, dir, *) {
    SetToggle(key, dir > 0)
}

SetToggle(key, on, *) {
    on := on ? 1 : 0
    if (Cfg[key] = on)
        return
    Cfg[key] := on
    Save(key)
    PaintToggle(key)
    switch key {
        case "OnTop":
            try WinSetAlwaysOnTop(on, "ahk_id " MainGui.Hwnd)
        case "ShowAreas":
            if on {
                UpdateOverlay()
                SetTimer(UpdateOverlay, 500)
            } else {
                SetTimer(UpdateOverlay, 0)
                HideOverlay()
            }
        case "ColorSafe":
            SetTimer(RebuildGui, -1)
        case "AqAuto":
            RefreshRobloxInfo()
        case "TotemAuto":
            TotemsChanged()
        case "SovAuto":
            PaintSovStatus()
        case "AutoReconnect":
            if Running
                SetTimer(WatchConnection, on ? 3000 : 0)
    }
    Say(on ? "on" : "off")
}

CycleChoice(key, dir, *) {
    opts := []
    if Choices.Has(key)
        opts := Choices[key].options
    else if SegCtls.Has(key)
        for s in SegCtls[key]
            opts.Push([s.value, s.text])
    if !opts.Length
        return
    idx := 1
    for i, o in opts
        if (o[1] = Cfg[key])
            idx := i
    SetChoiceValue(key, opts[Mod(idx - 1 + dir + opts.Length, opts.Length) + 1][1])
}

SetChoiceValue(key, value, *) {
    if (Cfg[key] = value)
        return
    Cfg[key] := value
    Save(key)
    PaintSegs(key), PaintChoice(key)
    if (key = "Theme") {
        SetTimer(RebuildGui, -1)
    } else if (key = "ControlStyle") {
        RodsChanged()
    }
    Say(ChoiceText(key))
}

SpokenValue(key, *) {
    if NumSpec.Has(key)
        return (StepText(key) = "Auto" || StepText(key) = "Off") ? StepText(key) : Cfg[key] " " UnitWord(NumSpec[key].unit)
    if KeyBtns.Has(key)
        return Cfg[key] = "" ? "not set" : KeyName(Cfg[key])
    if Toggles.Has(key)
        return Cfg[key] ? "on" : "off"
    return ChoiceText(key)
}

UnitWord(u) {
    static words := Map("ms", "milliseconds", "s", "seconds", "%", "percent", "min", "minutes", "reels", "reels")
    return words.Has(u) ? words[u] : ""
}

ZoomStep(dir, *) {
    cur := Cfg["Zoom"], nxt := cur
    if (dir > 0) {
        for z in ZoomSteps {
            if (z > cur) {
                nxt := z
                break
            }
        }
    } else {
        Loop ZoomSteps.Length {
            z := ZoomSteps[ZoomSteps.Length - A_Index + 1]
            if (z < cur) {
                nxt := z
                break
            }
        }
    }
    SetZoom(nxt)
}

SetZoom(pct, *) {
    pct := Clamp(pct, 80, 200)
    if (pct = Cfg["Zoom"])
        return
    Cfg["Zoom"] := pct
    Save("Zoom")
    try Steppers["Zoom"].Text := pct
    try UI.sbZoom.Text := pct "%"
    Say("Zoom " pct " percent")
    SetTimer(RebuildGui, -300)
}

CaptureKeyFor(key, *) {
    global Capturing
    if (Capturing || Calibrating)
        return
    ti := RegExMatch(key, "^Totem:(\d+)$", &tm) ? Integer(tm[1]) : 0
    if (ti && ti > Totems.Length)
        return
    if Running
        StopMacro()
    Capturing := true
    b := ti ? UI.totemRows[ti].key : KeyBtns[key]
    b.Text := "Press a key"
    b.SetFont("c" Pal.wait)
    Say("Press a key")
    Suspend(true)
    ih := InputHook("L0 T8")
    ih.KeyOpt("{All}", "ES")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-ES")
    ih.Start()
    ih.Wait()
    Suspend(false)
    k := (ih.EndReason = "EndKey") ? ih.EndKey : ""
    note := ""
    if (ti && k != "" && k != "Escape") {
        problem := KeyProblem(key, k)
        if (problem != "")
            note := problem
        else
            Totems[ti].slot := k, SaveTotems()
    } else if (k != "" && k != "Escape") {
        problem := KeyProblem(key, k)
        if (problem != "") {
            note := problem
        } else {
            old := Cfg[key]
            Cfg[key] := k
            if ((key = "ToggleKey" || key = "ExitKey") && !BindHotkeys()) {
                Cfg[key] := old
                BindHotkeys()
                note := KeyName(k) " can't be used as a hotkey."
            } else {
                Save(key)
            }
        }
    }
    try {
        if ti
            TotemsChanged()
        else
            b.Text := Cfg[key] = "" ? "Not set" : KeyName(Cfg[key]), b.SetFont("c" Pal.text)
    }
    Capturing := false
    UpdateStartControls()
    BuildMenus()
    if (note != "")
        SetPhase("error", "Key not changed", note)
    else
        SetPhase("idle", "Ready", IdleHint())
    Say(note != "" ? note : KeyName(Cfg[key]))
}

KeyProblem(target, k) {
    hot := (target = "ToggleKey" || target = "ExitKey")
    if (k = "Enter" || k = "NumpadEnter")
        return "Enter is used for shaking. Pick a different key."
    if (hot && RegExMatch(k, "i)^(Tab|Space|Escape|Up|Down|Left|Right|Backspace|Delete)$"))
        return KeyName(k) " is needed for normal typing and moving around. Pick a function key instead."
    uses := Map("ToggleKey", "start and stop", "ExitKey", "quit", "NavKey", "UI navigation", "RodKey", "the rod slot"
        , "SovInvKey", "the inventory")
    for name, what in uses {
        if (name = target || Cfg[name] != k)
            continue
        if (hot || name = "ToggleKey" || name = "ExitKey" || (SubStr(target, 1, 6) = "Totem:" && name = "RodKey"))
            return KeyName(k) " is already set for " what "."
    }
    return ""
}

BindHotkeys() {
    static bound := Map()
    ok := true
    for name, fn in Map("ToggleKey", HK_Toggle, "ExitKey", HK_Quit) {
        if bound.Has(name)
            try Hotkey(bound[name], "Off")
        try {
            Hotkey(Cfg[name], fn, "On")
            bound[name] := Cfg[name]
        } catch {
            ok := false
        }
    }
    return ok
}

HK_Toggle(*) => ToggleMacro()
HK_Quit(*) => ExitApp()

ConfirmReset() {
    Dialog.Show("Reset all settings?", "This deletes FischMacro.ini, including your rod looks, totem schedule and alert settings, then restarts it.", "Reset", DoReset, "Cancel")
}

DoReset(*) {
    global NoSave
    if Running
        StopMacro()
    NoSave := true
    try FileDelete(IniPath)
    Reload()
}

ShowShortcuts() {
    Dialog.Show("Keyboard shortcuts"
        , "Tab and Shift+Tab move between controls.`nArrow keys change the focused value.`nSpace or Enter activates it.`n"
        . "Ctrl+Tab and Ctrl+Shift+Tab switch tabs. Ctrl+1 to Ctrl+8 jump to the main tabs.`n"
        . "In a text field, Enter finishes and Esc cancels.`n"
        . "Ctrl+plus, Ctrl+minus and Ctrl+0 zoom. Ctrl+mouse wheel zooms too.`n"
        . "Alt+F, Alt+M, Alt+V and Alt+H open the menus.`n"
        . KeyName(Cfg["ToggleKey"]) " starts and stops fishing from any window. " KeyName(Cfg["ExitKey"]) " quits.")
}

ShowAbout() {
    Dialog.Show("About " APP_NAME
        , APP_NAME " " APP_VER " on AutoHotkey " A_AhkVersion ".`n"
        . "It reads the screen and presses keys. It never touches game memory.`n"
        . "Rod skins are learned by watching which block moves with the bar.`n"
        . "Library rod colors and the aquarium panel layout come from DeepFish v1.0.3.`n"
        . "Macros break Roblox's terms of use, and unattended farming is what gets accounts banned.")
}

RefreshRobloxInfo(*) {
    global RobloxInfo
    UsePhysicalPixels()
    h := FindRoblox()
    cr := h ? ClientRect(h) : 0
    RobloxInfo := {found: h != 0, w: cr ? cr.w : 0, h: cr ? cr.h : 0}
    if !UiReady
        return
    try {
        if h {
            UI.hRbx.Text := cr ? Format("Roblox found, {} × {}", cr.w, cr.h) : "Roblox found, but its window is minimized"
            UI.iRbx.Text := cr ? Format("{} × {}", cr.w, cr.h) : "Minimized"
            col := Pal.accent
        } else {
            UI.hRbx.Text := "Roblox isn't open yet"
            UI.iRbx.Text := "Not found"
            col := Pal.wait
        }
        UI.hDot.SetFont("c" col)
        UI.iAq.Text := NextJobText()
    }
}

;==============================================================================
; Mouse. Text controls are transparent to the mouse, so the window receives
; the messages and the control under the cursor is looked up by position.
;==============================================================================
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    x := x >= 0x8000 ? x - 0x10000 : x, y := y >= 0x8000 ? y - 0x10000 : y
    if (IsObject(Dialog.g) && hwnd = Dialog.g.Hwnd) {
        h := ChildAt(hwnd, x, y)
        if (h && Clickables.Has(h)) {
            Press(h, Clickables[h])
            return 0
        }
        PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)
        return 0
    }
    ; the sign-in window, and the opened sidebar: their buttons and tabs
    if ((Login.g && hwnd = Login.g.Hwnd) || (Flyout.g && hwnd = Flyout.g.Hwnd)) {
        h := ChildAt(hwnd, x, y)
        if (h && Clickables.Has(h))
            Press(h, Clickables[h])
        else if (Login.g && hwnd = Login.g.Hwnd)
            PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)      ; drag the sign-in screen by any empty spot
        return 0
    }
    ; the small panel while fishing: Stop, or drag it anywhere
    if (Hud.g && hwnd = Hud.g.Hwnd) {
        if (ChildAt(hwnd, x, y) = Hud.stop.Hwnd)
            SetTimer(ToggleMacro, -1)
        else
            PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)
        return 0
    }
    if (!IsObject(MainGui) || hwnd != MainGui.Hwnd || !UiReady)
        return
    zone := ResizeZone(x, y)
    if (zone != "") {
        SetTimer(ResizeLoop.Bind(zone), -1)
        return 0
    }
    if FocusOn
        FocusClear()
    h := ChildAt(hwnd, x, y)
    if (h && Clickables.Has(h)) {
        Press(h, Clickables[h])
        return 0
    }
    if (msg = 0x203 && y < ToPhys(TAB_H)) {
        SetTimer(ToggleMaximize, -1)
        return 0
    }
    if !Maxed
        PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)   ; drag the window
}

Press(h, e) {
    switch e.kind {
        case "btn", "dlg":
            if e.fn
                SetTimer(e.fn, -1)
        case "step":
            StepSetting(e.key, e.dir)
            Repeat.key := e.key, Repeat.dir := e.dir, Repeat.hwnd := h, Repeat.n := 0
            SetTimer(RepeatStep, -380)
        case "toggle":
            FlipToggle(e.key)
        case "seg":
            SetChoiceValue(e.key, e.value)
        case "tab":
            NavPress(e.name)
        case "key":
            SetTimer(CaptureKeyFor.Bind(e.key), -1)
        case "menu":
            SetTimer(OpenMenu.Bind(e.name), -1)
        case "choice":
            SetTimer(OpenChoiceMenu.Bind(e.key), -1)
        case "sbmenu":
            SetTimer(OpenMenu.Bind(e.menu, e.obj), -1)
        case "rodsel":
            SelectRod(e.i)
        case "tt":
            TotemOp(e.op, e.i)
    }
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    if (UiReady && ((Flyout.g && hwnd = Flyout.g.Hwnd) || (Login.g && hwnd = Login.g.Hwnd))) {
        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
        SetHover(ChildAt(hwnd, x >= 0x8000 ? x - 0x10000 : x, y >= 0x8000 ? y - 0x10000 : y))
        return
    }
    if (!IsObject(MainGui) || hwnd != MainGui.Hwnd || !UiReady)
        return
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    x := x >= 0x8000 ? x - 0x10000 : x, y := y >= 0x8000 ? y - 0x10000 : y
    if (x < ToPhys(SIDEBAR_W) && y > ToPhys(46) && !FocusOn && !Flyout.isOpen)
        SetTimer(FlyoutIntent, -90)                     ; resting on the icon strip opens the full sidebar
    h := ChildAt(hwnd, x, y)
    SetHover(h)
    if !FocusOn
        ShowDesc(h && DescOf.Has(h) ? DescOf[h] : "")
}

WM_MOUSEWHEEL(wParam, lParam, msg, hwnd) {
    if (!IsObject(MainGui) || !UiReady)
        return
    dir := ((wParam >> 16) & 0xFFFF) >= 0x8000 ? -1 : 1
    if (GetKeyState("Ctrl") && WinActive("ahk_id " MainGui.Hwnd)) {
        ZoomStep(dir)
        return 0
    }
    h := ChildAtCursor()
    if !(h && Clickables.Has(h))
        return
    e := Clickables[h]
    if (e.HasOwnProp("key") && NumSpec.Has(e.key)) {
        StepSetting(e.key, dir)
        return 0
    }
}

WM_SETCURSOR(wParam, lParam, msg, hwnd) {
    if (FreezeHwnd && DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = FreezeHwnd) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32515, "Ptr"))
        return true
    }
    if (IsObject(MainGui) && UiReady && hwnd = MainGui.Hwnd && !Maxed) {
        pt := CursorClient()
        zone := ResizeZone(pt.x, pt.y)
        if (zone != "") {
            id := (zone = "rb") ? 32642 : (zone = "r") ? 32644 : 32645
            DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", id, "Ptr"))
            return true
        }
    }
}

; Paints the Notepad-style bands behind the controls.
WM_ERASEBKGND(wParam, lParam, msg, hwnd) {
    if (!IsObject(MainGui) || hwnd != MainGui.Hwnd)
        return
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
    W := NumGet(rc, 8, "Int"), H := NumGet(rc, 12, "Int")
    sw := ToPhys(SIDEBAR_W), s := ToPhys(STATUS_H), one := Max(1, ToPhys(1))
    FillBand(wParam, 0, 0, sw, H, Pal.strip)                            ; sidebar
    FillBand(wParam, sw, 0, sw + one, H, Pal.seam)
    FillBand(wParam, sw + one, 0, W, H - s - one, Pal.content)          ; page
    FillBand(wParam, sw + one, H - s - one, W, H - s, Pal.seam)
    FillBand(wParam, sw + one, H - s, W, H, Pal.bar)                    ; status line
    ; depth: the sidebar casts a soft shadow onto the page, and the status
    ; line a shorter one upward (none in high contrast)
    if (Cfg["Theme"] != "High contrast") {
        n := ToPhys(9)
        loop n {
            i := A_Index - 1
            FillBand(wParam, sw + one + i, 0, sw + one + i + 1, H - s - one, Mix(Pal.content, "000000", 0.30 * (1 - i / n) ** 2))
        }
        m := ToPhys(5)
        loop m {
            i := A_Index - 1
            FillBand(wParam, sw + one + n, H - s - one - 1 - i, W, H - s - one - i, Mix(Pal.content, "000000", 0.20 * (1 - i / m) ** 2))
        }
    }
    return 1
}

ResizeZone(x, y) {
    if (Maxed || !IsObject(MainGui))
        return ""
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", MainGui.Hwnd, "Ptr", rc)
    W := NumGet(rc, 8, "Int"), H := NumGet(rc, 12, "Int")
    c := ToPhys(14), e := Max(4, ToPhys(5))
    if (x >= W - c && y >= H - c)
        return "rb"
    if (x >= W - e && y > ToPhys(TAB_H))
        return "r"
    if (y >= H - e)
        return "b"
    return ""
}

SetHover(h) {
    global Hover
    if (h = Hover)
        return
    same := h && Hover && Clickables.Has(h) && Clickables.Has(Hover) && Clickables[h] = Clickables[Hover]
    if (!same && Hover)
        Paint(Hover, false)
    Hover := h
    if (!same && h && Clickables.Has(h) && Clickables[h].HasOwnProp("hv")) {
        Paint(h, true)
        SetTimer(HoverWatch, 60)
    }
}

HoverWatch() {
    h := ChildAtCursor()
    if (h != Hover)
        SetHover(h)
    if !Hover
        SetTimer(HoverWatch, 0)
}

Paint(h, hot) {
    if !Clickables.Has(h)
        return
    e := Clickables[h]
    if e.HasOwnProp("onHover") {                ; (a drawn button animates its own hover)
        f := e.onHover
        f(hot)
        return
    }
    if !e.HasOwnProp("hv")
        return
    for c in (e.HasOwnProp("objs") ? e.objs : [e.obj]) {
        try {
            if (e.HasOwnProp("hvText") && e.hvText != "")
                c.SetFont("c" (hot ? e.hvText : Pal.text))
            if (e.bg = e.hv || c.Type = "Pic")
                c.Opt("Background" (hot ? e.hv : e.bg)), c.Redraw()
            else
                FadeBack(c, hot ? e.bg : e.hv, hot ? e.hv : e.bg, hot ? 110 : 170, "hv" c.Hwnd)
        }
    }
}

ShowDesc(text) {
    if !UiReady
        return
    want := text != "" ? text : Pages[CurTab].desc
    try {
        if (UI.desc.Text != want)
            UI.desc.Text := want
    }
}

CursorClient() {
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    DllCall("ScreenToClient", "Ptr", MainGui.Hwnd, "Ptr", pt)
    return {x: NumGet(pt, 0, "Int"), y: NumGet(pt, 4, "Int")}
}

ChildAtCursor() {
    if !IsObject(MainGui)
        return 0
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    top := DllCall("WindowFromPoint", "Int64", NumGet(pt, 0, "Int64"), "Ptr")
    for pop in [Flyout.g, Login.g]
        if (pop && (top = pop.Hwnd || DllCall("GetAncestor", "Ptr", top, "UInt", 1, "Ptr") = pop.Hwnd)) {
            DllCall("ScreenToClient", "Ptr", pop.Hwnd, "Ptr", pt)
            return ChildAt(pop.Hwnd, NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
        }
    if (top != MainGui.Hwnd && DllCall("GetAncestor", "Ptr", top, "UInt", 1, "Ptr") != MainGui.Hwnd)
        return 0
    DllCall("ScreenToClient", "Ptr", MainGui.Hwnd, "Ptr", pt)
    return ChildAt(MainGui.Hwnd, NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
}

ChildAt(parent, x, y) {
    h := DllCall("ChildWindowFromPointEx", "Ptr", parent, "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 1, "Ptr")
    return (h = parent) ? 0 : h
}

;==============================================================================
; Keyboard: a focus ring that walks the toolbar and the current page.
;==============================================================================
FocusList() {
    list := []
    for it in FocusGlobal
        if (!it.HasOwnProp("navMode") || it.navMode = UI.navMode)   ; skip the hidden sidebar set
            list.Push(it)
    for it in Pages[CurTab].focus
        list.Push(it)
    return list
}

FocusMove(dir) {
    global FocusIdx, FocusOn
    list := FocusList()
    if !list.Length
        return
    if !FocusOn {
        FocusOn := true
        nGlobal := 0                     ; the sidebar items in the list (the hidden set is skipped)
        for it in FocusGlobal
            nGlobal += (!it.HasOwnProp("navMode") || it.navMode = UI.navMode)
        FocusIdx := dir > 0 ? Min(nGlobal + 1, list.Length) : list.Length
    } else {
        FocusIdx := Mod(FocusIdx - 1 + dir + list.Length, list.Length) + 1
    }
    ShowFocus(list[FocusIdx])
}

ShowFocus(item, speak := true) {
    x1 := 99999, y1 := 99999, x2 := -99999, y2 := -99999
    for c in item.ctls {
        c.GetPos(&cx, &cy, &cw, &ch)
        x1 := Min(x1, cx), y1 := Min(y1, cy), x2 := Max(x2, cx + cw), y2 := Max(y2, cy + ch)
    }
    o := ZS(3), t := Max(2, ZS(Pal.ring)), r := UI.ring
    r[1].Move(x1 - o - t, y1 - o - t, x2 - x1 + 2 * (o + t), t)
    r[2].Move(x1 - o - t, y2 + o, x2 - x1 + 2 * (o + t), t)
    r[3].Move(x1 - o - t, y1 - o, t, y2 - y1 + 2 * o)
    r[4].Move(x2 + o, y1 - o, t, y2 - y1 + 2 * o)
    for c in r {
        c.Visible := true
        c.Redraw()
    }
    if (item.desc != "")
        ShowDesc(item.desc)
    if speak
        Say(item.name (item.value ? ", " item.value.Call() : ""))
}

HideRing() {
    if UI.HasOwnProp("ring")
        for c in UI.ring
            try c.Visible := false
}

FocusActivate() {
    list := FocusList()
    if (!FocusOn || FocusIdx < 1 || FocusIdx > list.Length)
        return FocusMove(1)
    it := list[FocusIdx]
    if it.act
        it.act.Call()
    else if it.adj
        it.adj.Call(1)
    AfterFocusChange(it)
}

FocusAdjust(dir) {
    list := FocusList()
    if (!FocusOn || FocusIdx < 1 || FocusIdx > list.Length)
        return
    it := list[FocusIdx]
    if it.adj {
        it.adj.Call(dir)
        AfterFocusChange(it)
    }
}

AfterFocusChange(it) {
    if (!FocusOn || !UiReady)
        return
    list := FocusList()
    if (FocusIdx <= list.Length)
        try ShowFocus(list[FocusIdx], false)
    if it.value
        try Say(it.value.Call())
}

FocusClear() {
    global FocusOn
    FocusOn := false
    HideRing()
    ShowDesc("")
}

; Keyboard for this window. Keys arrive as ordinary key messages while the
; window has focus, so no global keyboard hook is installed and nothing
; reacts while another window is in front. Returning 0 marks a key handled.
WM_KEYDOWN(wParam, lParam, msg, hwnd) {
    top := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    rep := (lParam >> 30) & 1
    if (IsObject(Dialog.g) && top = Dialog.g.Hwnd)
        return DialogKey(wParam, rep)
    if (!IsObject(MainGui) || top != MainGui.Hwnd || !UiReady || Capturing || Calibrating || MenuOpen)
        return
    if EditCtls.Has(hwnd)
        return EditKey(EditCtls[hwnd], wParam, msg = 0x104)
    return PanelKey(wParam, msg = 0x104, rep)
}

; In a text field every key types, except Tab (moves on), Enter (done) and
; Esc (cancel), plus the Alt menus.
EditKey(ed, vk, alt) {
    if alt
        return PanelKey(vk, true, 0)
    switch vk {
        case 0x09:
            try MainGui.Focus()
            FocusMove(GetKeyState("Shift") ? -1 : 1)
            return 0
        case 0x0D:
            if (ed.key = "rodtype")
                UseTypedRod()
            else if (ed.key = "rename")
                CommitRename(true)
            else
                try MainGui.Focus()
            return 0
        case 0x1B:
            if (ed.key = "rename")
                CommitRename(false)
            else
                try MainGui.Focus()
            return 0
    }
}

; A lone Alt tap would put the window into system-menu mode and swallow the
; next key, so the release is consumed.
WM_SYSKEYUP(wParam, lParam, msg, hwnd) {
    if (wParam = 0x12 && IsObject(MainGui) && DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = MainGui.Hwnd)
        return 0
}

DialogKey(vk, rep) {
    if (vk = 0x0D || vk = 0x20) {
        if !rep
            SetTimer(ObjBindMethod(Dialog, "Ok"), -1)
        return 0
    }
    if (vk = 0x1B) {
        Dialog.Close()
        return 0
    }
}

PanelKey(vk, alt, rep) {
    ; Tab and the arrow keys repeat while held; everything else acts once.
    repeats := (vk = 0x09 || (vk >= 0x25 && vk <= 0x28))
    if (rep && !repeats) {
        if (alt || vk = 0x0D || vk = 0x20 || vk = 0x1B || GetKeyState("Ctrl"))
            return 0
        return
    }
    if alt {
        switch vk {
            case 0x46: SetTimer(OpenMenu.Bind("File"), -1)
            case 0x4D: SetTimer(OpenMenu.Bind("Macro"), -1)
            case 0x56: SetTimer(OpenMenu.Bind("View"), -1)
            case 0x48: SetTimer(OpenMenu.Bind("Help"), -1)
            case 0x79: SetTimer(OpenMenu.Bind("File"), -1)
            default: return
        }
        return 0
    }
    shift := GetKeyState("Shift")
    if GetKeyState("Ctrl") {
        switch vk {
            case 0x09: CycleTab(shift ? -1 : 1)
            case 0x22: CycleTab(1)
            case 0x21: CycleTab(-1)
            case 0xBB, 0x6B: ZoomStep(1)
            case 0xBD, 0x6D: ZoomStep(-1)
            case 0x30, 0x60: SetZoom(100)
            case 0x53:
                FlushSaves()
                SetDetail("Settings saved.")
            default:
                if (vk >= 0x31 && vk <= 0x30 + BasicTabs.Length)
                    SwitchTab(BasicTabs[vk - 0x30])
                else
                    return
        }
        return 0
    }
    switch vk {
        case 0x09: FocusMove(shift ? -1 : 1)
        case 0x28: FocusMove(1)
        case 0x26: FocusMove(-1)
        case 0x25: FocusAdjust(-1)
        case 0x27: FocusAdjust(1)
        case 0x20, 0x0D: FocusActivate()
        case 0x1B: FocusClear()
        case 0x79: SetTimer(OpenMenu.Bind("File"), -1)
        default: return
    }
    return 0
}

;==============================================================================
; Menus. Popup menus follow the theme through uxtheme's app dark mode.
;==============================================================================
BuildMenus() {
    global Menus, StartItemName
    Menus := Map()
    ApplyMenuTheme()
    f := Menu()
    f.Add("Save settings now`tCtrl+S", (*) => (FlushSaves(), SetDetail("Settings saved.")))
    f.Add("Open settings folder", (*) => OpenSettingsFolder())
    f.Add()
    f.Add("Reset all settings…", (*) => ConfirmReset())
    f.Add()
    f.Add("Exit`t" KeyName(Cfg["ExitKey"]), (*) => ExitApp())
    Menus["File"] := f
    style := Menu()
    style.Add("Physics, learns your rod", SetChoiceValue.Bind("ControlStyle", "physics"))
    style.Add("Simple look-ahead", SetChoiceValue.Bind("ControlStyle", "simple"))
    Menus["Style"] := style
    m := Menu()
    StartItemName := "Start fishing`t" KeyName(Cfg["ToggleKey"])
    m.Add(StartItemName, (*) => ToggleMacro())
    m.Add("Run aquarium now", (*) => RunAquariumNow())
    m.Add("Use totems now", (*) => SetTimer(UseTotemsNow, -1))
    m.Add("Recharge Sovereign now", (*) => SetTimer(RechargeNow, -1))
    m.Add()
    m.Add("Set reel area and teach a look…", (*) => StartCalibrate("Reel"))
    m.Add("Set shake area…", (*) => StartCalibrate("Shake"))
    m.Add()
    m.Add("Control style", style)
    Menus["Macro"] := m
    th := Menu()
    for t in ["Black", "Dark", "Light", "High contrast"]
        th.Add(t, SetChoiceValue.Bind("Theme", t))
    Menus["Theme"] := th
    zm := Menu()
    for z in ZoomSteps
        zm.Add(z "%", SetZoom.Bind(z))
    Menus["Zoom"] := zm
    tabs := Menu()
    for i, t in TabNames
        tabs.Add(t "`tCtrl+" i, GoTab.Bind(t))
    Menus["Tabs"] := tabs
    v := Menu()
    v.Add("Go to tab", tabs)
    v.Add()
    v.Add("Theme", th)
    v.Add("Zoom", zm)
    v.Add("Zoom in`tCtrl+Plus", (*) => ZoomStep(1))
    v.Add("Zoom out`tCtrl+Minus", (*) => ZoomStep(-1))
    v.Add("Reset zoom`tCtrl+0", (*) => SetZoom(100))
    v.Add()
    v.Add("Show scan areas", (*) => FlipToggle("ShowAreas"))
    v.Add("Keep window on top", (*) => FlipToggle("OnTop"))
    v.Add("Color-blind safe colors", (*) => FlipToggle("ColorSafe"))
    v.Add("Reduce motion", (*) => FlipToggle("ReduceMotion"))
    Menus["View"] := v
    hm := Menu()
    hm.Add("Start menu", (*) => SwitchTab("Home"))
    hm.Add("Keyboard shortcuts", (*) => ShowShortcuts())
    hm.Add()
    hm.Add("About " APP_NAME, (*) => ShowAbout())
    Menus["Help"] := hm
}

RefreshMenus() {
    global StartItemName
    try {
        for i, t in TabNames
            SetCheck(Menus["Tabs"], t "`tCtrl+" i, CurTab = t)
        SetCheck(Menus["Style"], "Physics, learns your rod", Cfg["ControlStyle"] = "physics")
        SetCheck(Menus["Style"], "Simple look-ahead", Cfg["ControlStyle"] = "simple")
        for t in ["Black", "Dark", "Light", "High contrast"]
            SetCheck(Menus["Theme"], t, Cfg["Theme"] = t)
        for z in ZoomSteps
            SetCheck(Menus["Zoom"], z "%", Cfg["Zoom"] = z)
        for pair in [["Show scan areas", "ShowAreas"], ["Keep window on top", "OnTop"], ["Color-blind safe colors", "ColorSafe"], ["Reduce motion", "ReduceMotion"]]
            SetCheck(Menus["View"], pair[1], Cfg[pair[2]])
        want := ((Running || AqManual) ? "Stop`t" : "Start fishing`t") KeyName(Cfg["ToggleKey"])
        if (want != StartItemName) {
            Menus["Macro"].Rename(StartItemName, want)
            StartItemName := want
        }
    }
}

GoTab(name, *) => SwitchTab(name)

SetCheck(m, item, on) {
    if on
        m.Check(item)
    else
        m.Uncheck(item)
}

OpenMenu(name, anchor := 0, *) {
    global MenuOpen
    if (!Menus.Has(name) || MenuOpen || !IsObject(MainGui))
        return
    if (!IsObject(anchor) && UI.menuBtns.Has(name))
        anchor := UI.menuBtns[name]
    RefreshMenus()
    if IsObject(anchor) {
        WinGetPos(&x, &y, &w, &h, "ahk_id " anchor.Hwnd)
        y += h
    } else {
        MouseGetPos(&x, &y)
    }
    MenuOpen := true
    try Menus[name].Show(x, y)
    MenuOpen := false
}

OpenChoiceMenu(key, *) {
    global MenuOpen
    if (MenuOpen || !Choices.Has(key))
        return
    ch := Choices[key]
    m := Menu()
    for o in ch.options {
        m.Add(o[2], SetChoiceValue.Bind(key, o[1]))
        if (Cfg[key] = o[1])
            m.Check(o[2])
    }
    WinGetPos(&x, &y, &w, &h, "ahk_id " ch.ctl.Hwnd)
    MenuOpen := true
    try m.Show(x, y + h)
    MenuOpen := false
}

ApplyMenuTheme() {
    static ux := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
    if !ux
        return
    try {
        setMode := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 135, "Ptr")
        flush := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 136, "Ptr")
        if setMode
            DllCall(setMode, "Int", Pal.dark ? 2 : 3)
        if flush
            DllCall(flush)
    }
}

OpenSettingsFolder() {
    FlushSaves()
    if FileExist(IniPath)
        Run('explorer.exe /select,"' IniPath '"')
    else
        Run(A_ScriptDir)
}

; A small themed dialog owned by the main window.
class Dialog {
    static g := 0, okFn := 0
    static Show(title, body, okText := "Close", okFn := 0, cancelText := "", scrollH := 0) {
        this.Close()
        if !IsObject(MainGui)
            return
        g := Gui("-Caption +ToolWindow +Owner" MainGui.Hwnd (Cfg["OnTop"] ? " +AlwaysOnTop" : ""), title)
        g.BackColor := Pal.bar
        g.MarginX := 0, g.MarginY := 0
        w := 460
        SetFontFor(g, "norm s" FZ(14) " c" Pal.text, "display")
        g.Add("Text", Format("x{} y{} w{} Background{}", ZS(24), ZS(20), ZS(w - 48), Pal.bar), title)
        SetFontFor(g, "norm s" FZ(10) " c" Pal.text, "body")
        if scrollH {
            ; a long text (the update log) scrolls in a box of fixed height
            b := g.Add("Edit", Format("x{} y{} w{} h{} ReadOnly Multi VScroll -E0x200 -TabStop Background{}", ZS(24), ZS(58), ZS(w - 40), ZS(scrollH), Pal.bar), StrReplace(body, "`n", "`r`n"))
            DllCall("HideCaret", "Ptr", b.Hwnd)
        } else
            b := g.Add("Text", Format("x{} y{} w{} Background{}", ZS(24), ZS(58), ZS(w - 48), Pal.bar), body)
        b.GetPos(, &by, , &bh)
        y := by + bh + ZS(22), bw := ZS(120), bh2 := ZS(32)
        SetFontFor(g, "norm s" FZ(10) " c" Pal.ink, "body")
        ok := g.Add("Text", Format("x{} y{} w{} h{} Center 0x200 Background{}", ZS(w - 24 - 120), y, bw, bh2, Pal.accent), okText)
        Clickables[ok.Hwnd] := {kind: "dlg", fn: ObjBindMethod(Dialog, "Ok"), obj: ok}
        if (cancelText != "") {
            SetFontFor(g, "norm s" FZ(10) " c" Pal.text, "body")
            cn := g.Add("Text", Format("x{} y{} w{} h{} Center 0x200 Background{}", ZS(w - 24 - 252), y, bw, bh2, Pal.field), cancelText)
            Clickables[cn.Hwnd] := {kind: "dlg", fn: ObjBindMethod(Dialog, "Close"), obj: cn}
        }
        g.OnEvent("Escape", (*) => Dialog.Close())
        g.Show(Format("Hide w{} h{}", ZS(w), y + bh2 + ZS(22)))
        WinRect(g.Hwnd, &dx, &dy, &dw, &dh)
        WinGetPos(&mx, &my, &mw, &mh, "ahk_id " MainGui.Hwnd)
        fade := !Cfg["ReduceMotion"]
        if fade
            WinSetTransparent(0, g.Hwnd)
        g.Show(Format("x{} y{}", mx + (mw - dw) // 2, my + (mh - dh) // 3))
        StyleWindow(g.Hwnd)
        if fade
            FadeWindow(g.Hwnd, 180)
        this.g := g, this.okFn := okFn
        Say(title ". " StrReplace(body, "`n", " "))
    }
    static Ok(*) {
        fn := this.okFn
        this.Close()
        if fn
            fn.Call()
    }
    static Close(*) {
        if this.g {
            try this.g.Destroy()
            this.g := 0
        }
    }
}

;==============================================================================
; Speech and sound cues
;==============================================================================
Say(text) {
    global Voice
    if (!Cfg["Speak"] || text = "")
        return
    try {
        if !IsObject(Voice)
            Voice := ComObject("SAPI.SpVoice")
        Voice.Speak(text, 3)      ; asynchronous, replacing anything still being spoken
    }
}

Cue(kind) {
    static sounds := Map("start", "*64", "catch", "*-1", "pause", "*48", "error", "*16")
    if Cfg["Sounds"]
        try SoundPlay(sounds.Has(kind) ? sounds[kind] : "*-1")
}

;==============================================================================
; Area setup: freeze the Roblox window, then drag a box, sample colours or
; click the aquarium button.
;==============================================================================
StartCalibrate(kind) {
    SetTimer(Calibrate.Bind(kind), -1)
}

Calibrate(kind) {
    global Calibrating, CalFlag, FreezeHwnd
    if (Calibrating || Capturing || AqManual)
        return
    if Running
        StopMacro()
    UsePhysicalPixels()
    hwnd := FindRoblox()
    if !hwnd {
        SetPhase("error", "Roblox isn't open", "Open Fisch first, then try again.")
        Cue("error")
        return
    }
    Calibrating := true
    CalFlag := ""
    HideOverlay()
    MainGui.Hide()
    try WinActivate("ahk_id " hwnd)
    Hotkey("*Esc", CalEsc, "On")
    Hotkey("*Enter", CalEnter, "On")
    fz := 0, sel := 0, hbm := 0, result := "cancel", what := ""
    try {
        if (kind = "Reel")
            Banner.Show("Hook a fish. When the reel bar is on screen, press Ctrl to freeze it.`nEsc cancels.", hwnd)
        else
            Banner.Show("Press Ctrl to freeze the screen.`nEsc cancels.", hwnd)
        if !WaitForCtrl()
            throw Error("cancelled")
        cr := ClientRect(hwnd)
        if !cr
            throw Error("cancelled")
        Banner.Hide()
        Sleep 80
        hbm := CaptureBitmap(cr.x, cr.y, cr.w, cr.h)
        fz := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
        fz.MarginX := 0, fz.MarginY := 0
        fz.Add("Picture", Format("x0 y0 w{} h{}", cr.w, cr.h), "HBITMAP:*" hbm)
        fz.Show(Format("x{} y{} w{} h{}", cr.x, cr.y, cr.w, cr.h))
        FreezeHwnd := fz.Hwnd
        if false {
        } else {
            Banner.Show(kind = "Reel"
                ? "Drag a box just inside the reel track. Drag again to redo it.`nEnter saves the box. Esc cancels."
                : "Drag a box over the area where shake buttons pop up.`nEnter saves the box. Esc cancels.", hwnd)
            sel := Outline(Pal.accent)
            box := DragBox(sel)
            if !box
                throw Error("cancelled")
            Cfg[kind "X1"] := Clamp((box.x - cr.x) / cr.w, 0, 1)
            Cfg[kind "Y1"] := Clamp((box.y - cr.y) / cr.h, 0, 1)
            Cfg[kind "X2"] := Clamp((box.x + box.w - cr.x) / cr.w, 0, 1)
            Cfg[kind "Y2"] := Clamp((box.y + box.h - cr.y) / cr.h, 0, 1)
            for k in ["X1", "Y1", "X2", "Y2"]
                Save(kind k)
            what := kind " area saved"
        }
        result := "saved"
    } catch as err {
        if (err.Message != "cancelled")
            result := "failed: " err.Message
    } finally {
        try Hotkey("*Esc", "Off")
        try Hotkey("*Enter", "Off")
        Banner.Hide()
        FreezeHwnd := 0
        if sel
            sel.Destroy()
        if fz
            fz.Destroy()
        if hbm
            DllCall("DeleteObject", "Ptr", hbm)
        MainGui.Show()
        Calibrating := false
        if Cfg["ShowAreas"]
            UpdateOverlay()
    }
    if (result = "saved") {
        SetPhase("idle", what, IdleHint())
        LogEvent(what)
    } else if (result = "cancel") {
        SetPhase("idle", "Ready", "Setup cancelled. Nothing changed.")
    } else {
        SetPhase("error", "Setup failed", SubStr(result, 9))
    }
}

CalEsc(*) {
    global CalFlag := "esc"
}

CalEnter(*) {
    global CalFlag := "enter"
}

WaitForCtrl() {
    KeyWait("Ctrl", "T3")
    t0 := A_TickCount
    while (CalFlag != "esc" && A_TickCount - t0 < 180000) {
        if GetKeyState("Ctrl", "P")
            return true
        Sleep 15
    }
    return false
}

DragBox(sel) {
    global CalFlag
    CalFlag := "", box := 0
    KeyWait("LButton", "T3")
    loop {
        if (CalFlag = "esc")
            return 0
        if (CalFlag = "enter") {
            if box
                return box
            CalFlag := ""
        }
        if GetKeyState("LButton", "P") {
            MouseGetPos(&sx, &sy)
            x := sx, y := sy, w := 0, h := 0
            while GetKeyState("LButton", "P") {
                MouseGetPos(&mx, &my)
                x := Min(sx, mx), y := Min(sy, my), w := Abs(mx - sx), h := Abs(my - sy)
                if (w >= 3 && h >= 2)
                    sel.Show(x, y, w, h)
                Sleep 10
            }
            if (w >= 8 && h >= 3)
                box := {x: x, y: y, w: w, h: h}
            sel.Raise()
            Banner.Raise()
        }
        Sleep 10
    }
}


PickPoint() {
    global CalFlag
    CalFlag := ""
    KeyWait("LButton", "T3")
    loop {
        if (CalFlag = "esc")
            return 0
        if GetKeyState("LButton", "P") {
            MouseGetPos(&mx, &my)
            KeyWait("LButton", "T3")
            return {x: mx, y: my}
        }
        Sleep 10
    }
}

CaptureBitmap(x, y, w, h) {
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", sdc, "Int", w, "Int", h, "Ptr")
    old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", sdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    return hbm
}

; Instruction strip near the top of the Roblox window. Never takes focus.
class Banner {
    static g := 0
    static Show(msg, hwnd, swatch := "") {
        this.Hide()
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
        g.BackColor := Pal.bar
        g.MarginX := 0, g.MarginY := 0
        SetFontFor(g, "norm s" FZ(11) " c" Pal.text, "body")
        t := g.Add("Text", Format("x{} y{} Background{}", ZS(24), ZS(14), Pal.bar), msg)
        t.GetPos(, , &tw, &th)
        extra := 0
        if (swatch != "") {
            g.Add("Text", Format("x{} y{} w{} h{} Background{}", ZS(24) + tw + ZS(16), ZS(14) + (th - ZS(16)) // 2, ZS(16), ZS(16), swatch))
            extra := ZS(32)
        }
        g.Add("Text", Format("x0 y0 w{} h{} Background{}", Max(3, ZS(3)), th + ZS(28), Pal.accent))
        g.Show(Format("Hide w{} h{}", tw + extra + ZS(48), th + ZS(28)))
        WinRect(g.Hwnd, &bx, &by, &bw, &bh)
        cr := ClientRect(hwnd)
        x := cr ? cr.x + (cr.w - bw) // 2 : (A_ScreenWidth - bw) // 2
        y := cr ? cr.y + Round(cr.h * 0.05) : 40
        g.Show(Format("NA x{} y{}", x, y))
        RaiseNoActivate(g.Hwnd)
        StyleWindow(g.Hwnd)
        this.g := g
        Say(StrReplace(msg, "`n", " "))
    }
    static Raise() {
        if this.g
            RaiseNoActivate(this.g.Hwnd)
    }
    static Hide() {
        if this.g {
            try this.g.Destroy()
            this.g := 0
        }
    }
}

; Hollow rectangle drawn just outside a region. Never takes focus.
class Outline {
    __New(color, thick := 2) {
        this.t := thick, this.last := ""
        this.g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 -DPIScale")
        this.g.BackColor := color
    }
    Show(x, y, w, h) {
        t := this.t, ox := x - t, oy := y - t, ow := w + 2 * t, oh := h + 2 * t
        key := ox "," oy "," ow "," oh
        if (key = this.last)
            return
        this.last := key
        this.g.Show(Format("NA x{} y{} w{} h{}", ox, oy, ow, oh))
        WinSetRegion(Format("0-0 {1}-0 {1}-{2} 0-{2} 0-0 {3}-{3} {4}-{3} {4}-{5} {3}-{5} {3}-{3}"
            , ow, oh, t, ow - t, oh - t), "ahk_id " this.g.Hwnd)
        RaiseNoActivate(this.g.Hwnd)
    }
    Raise() {
        if (this.last != "")
            RaiseNoActivate(this.g.Hwnd)
    }
    Hide() {
        this.g.Hide()
        this.last := ""
    }
    Destroy() {
        try this.g.Destroy()
    }
}

UpdateOverlay() {
    global OutReel, OutShake, OutAq
    UsePhysicalPixels()
    if (!Cfg["ShowAreas"] || Calibrating)
        return HideOverlay()
    hwnd := FindRoblox()
    cr := hwnd ? ClientRect(hwnd) : 0
    if (!cr || WinGetMinMax("ahk_id " hwnd) = -1)
        return HideOverlay()
    if !OutReel
        OutReel := Outline(Pal.accent), OutShake := Outline(Pal.wait), OutAq := Outline(Pal.stop)
    a := AreaRect("Reel", cr), s := AreaRect("Shake", cr)
    OutShake.Show(s.x1, s.y1, s.w, s.h)
    OutReel.Show(a.x1, a.y1, a.w, a.h)
    nsp := UiSpot("aquariums", cr), nx := nsp.x, ny := nsp.y
    OutAq.Show(nx - 8, ny - 8, 16, 16)
}

HideOverlay() {
    if OutReel
        OutReel.Hide(), OutShake.Hide(), OutAq.Hide()
}

DestroyOverlays() {
    global OutReel, OutShake, OutAq
    if OutReel {
        OutReel.Destroy(), OutShake.Destroy(), OutAq.Destroy()
        OutReel := 0, OutShake := 0, OutAq := 0
    }
}

RaiseNoActivate(hwnd) {
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}

;==============================================================================
; Helpers
;==============================================================================
ZS(n) => Round(n * Zoom)
StepText(key) => (key = "Latency" && Cfg[key] = 0) ? "Auto" : Cfg[key]
FZ(n) => Max(6, Round(n * Zoom))
ToPhys(n) => Round(ZS(n) * A_ScreenDPI / 96)
Clamp(v, lo, hi) => Max(lo, Min(hi, v))
KeyName(k) => StrLen(k) = 1 ? StrUpper(k) : k
IdleHint() => "Press " KeyName(Cfg["ToggleKey"]) " to start or stop. " KeyName(Cfg["ExitKey"]) " quits."
IconOr(glyph, fallback) => HasIconFont ? glyph : fallback
PointOnScreen(x, y) => DllCall("MonitorFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 0, "Ptr") != 0

MonitorAt(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b)
            return A_Index
    }
    return MonitorGetPrimary()
}

; Adds a Text control in design units (scaled by the zoom level).
AddT(page, x, y, w, h, text, role, size, color, bg, extra := "") {
    return AddRaw(page, ZS(x), ZS(y), w = "" ? "" : ZS(w), h = "" ? "" : ZS(h), text, role, size, color, bg, extra)
}

; Adds a Text control in window units (already scaled).
AddRaw(page, x, y, w, h, text, role, size, color, bg, extra := "") {
    SetFontFor(MainGui, "norm s" FZ(size) " c" color, role)
    opts := "x" x " y" y (w != "" ? " w" w : "") (h != "" ? " h" h : "") " Background" bg (extra != "" ? " " extra : "")
    ctl := MainGui.Add("Text", opts, text)
    if (page != 0 && page != "")
        Pages[page].ctls.Push(ctl)
    return ctl
}

; Sets a font with fallbacks: later faces win when they are installed.
SetFontFor(g, opts, role := "body") {
    static faces := Map(
        "body", ["Tahoma", "Segoe UI"],
        "display", ["Tahoma", "Segoe UI Semibold", "Bahnschrift SemiBold"],
        "num", ["Tahoma", "Segoe UI", "Bahnschrift"]
    )
    if (role = "icon") {
        g.SetFont(opts, "Tahoma")
        if (IconFace != "")
            g.SetFont(opts, IconFace)
        return
    }
    ; The black-and-white theme renders text with greyscale smoothing, so no
    ; ClearType colour fringes appear around it.
    if (IsObject(Pal) && Pal.HasOwnProp("mono") && !InStr(opts, " q"))
        opts .= " q4"
    for face in faces[role]
        g.SetFont(opts, face)
}

DetectIconFont() {
    global HasIconFont, IconFace
    for f in [["SegoeIcons.ttf", "Segoe Fluent Icons"], ["segmdl2.ttf", "Segoe MDL2 Assets"]]
        if FileExist(A_WinDir "\Fonts\" f[1])
            return (HasIconFont := true, IconFace := f[2])
}

WinRect(hwnd, &x, &y, &w, &h) {
    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)
    x := NumGet(rc, 0, "Int"), y := NumGet(rc, 4, "Int")
    w := NumGet(rc, 8, "Int") - x, h := NumGet(rc, 12, "Int") - y
}

; Dark title handling, rounded corners and a hairline border on Windows 11.
StyleWindow(hwnd) {
    buf := Buffer(4)
    c := Integer("0x" Pal.seam)
    border := ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
    for attr, val in Map(20, Pal.dark ? 1 : 0, 33, 2, 34, border) {
        NumPut("UInt", val, buf)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", attr, "Ptr", buf, "UInt", 4)
    }
}

Brush(color) {
    if !Brushes.Has(color) {
        c := Integer("0x" color)
        Brushes[color] := DllCall("CreateSolidBrush", "UInt", ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF), "Ptr")
    }
    return Brushes[color]
}

FreeBrushes() {
    for k, b in Brushes
        DllCall("DeleteObject", "Ptr", b)
    Brushes.Clear()
}

FillBand(hdc, x1, y1, x2, y2, color) {
    rc := Buffer(16)
    NumPut("Int", x1, "Int", y1, "Int", x2, "Int", y2, rc)
    DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", Brush(color))
}

SetupTray() {
    try ApplyAppIcon()
    A_IconTip := APP_NAME
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Show window", (*) => ShowFromTray())
    A_TrayMenu.Add("Start or stop fishing", (*) => ToggleMacro())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Quit", (*) => ExitApp())
    A_TrayMenu.Default := "Show window"
}

ShowFromTray() {
    if Login.g {                                ; the sign-in screen is the program until a choice
        Login.g.Show()
        try WinActivate("ahk_id " Login.g.Hwnd)
        return
    }
    if IsObject(MainGui) {
        MainGui.Show()
        try WinActivate("ahk_id " MainGui.Hwnd)
    }
}

Cleanup(reason, code) {
    try DiscordAuth.Stop()
    ReleaseMouse()
    if !NoSave {
        SaveGeometry()
        FlushSaves()
    }
    FreeBrushes()
    if LiveHbm
        DllCall("DeleteObject", "Ptr", LiveHbm)
    try DllCall("DeleteObject", "Ptr", UI.logoHbm)
    try Gdip.Stop()
    try DllCall("winmm\timeEndPeriod", "UInt", 1)
}


;==============================================================================
; Vision. Finds the reel bar and the fish marker for any rod or skin.
;
; Every rod look (rod plus skin) is learned once and kept as a rod profile:
; colour palettes for the track, the bar and the fish, the bar width, and the
; rows where the track's top and bottom edges sit. A new look is learned by
; holding the mouse for a moment and seeing which block of pixels moved with
; the bar, so no colour is assumed in advance. Pixels are classified through
; a lookup table built on demand, which keeps each frame under a millisecond.
;==============================================================================

; Captures a block of rows around the reel area in one BitBlt.
; The screen area of srcW x srcH shrunk by f into a small image, averaged by
; Windows as it copies (HALFTONE), for looking at a large area quickly.
class ShrinkGrab extends BandGrab {
    __New(srcW, srcH, f) {
        super.__New(Max(8, srcW // f), Max(3, srcH // f))
        this.srcW := srcW, this.srcH := srcH
        DllCall("SetStretchBltMode", "Ptr", this.dc, "Int", 4)
        DllCall("SetBrushOrgEx", "Ptr", this.dc, "Int", 0, "Int", 0, "Ptr", 0)
    }
    Grab(x, y) {
        sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        DllCall("StretchBlt", "Ptr", this.dc, "Int", 0, "Int", 0, "Int", this.w, "Int", this.h
            , "Ptr", sdc, "Int", x, "Int", y, "Int", this.srcW, "Int", this.srcH, "UInt", 0x00CC0020)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    }
}

class BandGrab {
    __New(w, h) {
        this.w := w := Max(8, Integer(w)), this.h := h := Max(3, Integer(h)), this.stride := w * 4
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
        NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
        this.dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        this.bmp := DllCall("CreateDIBSection", "Ptr", this.dc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        this.bits := bits
        this.old := DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.bmp, "Ptr")
        this.cols := Buffer(w * 4, 0)      ; colour of each column (median of three rows)
        this.lab := Buffer(w + 1, 0)       ; class of each column
    }
    Grab(x, y) {
        sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        DllCall("BitBlt", "Ptr", this.dc, "Int", 0, "Int", 0, "Int", this.w, "Int", this.h
            , "Ptr", sdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    }
    __Delete() {
        DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.old)
        DllCall("DeleteObject", "Ptr", this.bmp)
        DllCall("DeleteDC", "Ptr", this.dc)
    }
}

; Geometry of the captured band: the reel area plus a margin above and below,
; where the track's edges are. r1..r3 are sample rows inside the track.
VisionGeo(a) {
    m := Max(4, Round(a.h * 0.9))
    geo := {x: a.x1, y: a.y1 - m, w: a.w, h: a.h + 2 * m + 1, m: m, ih: Max(1, a.h)}
    geo.r1 := m + Round(a.h * 0.25), geo.r2 := m + Round(a.h * 0.5), geo.r3 := m + Round(a.h * 0.75)
    return geo
}

VisionGrab(b, geo) {
    b.Grab(geo.x, geo.y)
    b.geo := geo
    ColumnColors(b, geo)
}

; Colour of each column: the per-channel median of three rows inside the
; track, which ignores a thin highlight or outline crossing one of them.
ColumnColors(b, geo) {
    p := b.bits, s := b.stride, o1 := geo.r1 * s, o2 := geo.r2 * s, o3 := geo.r3 * s
    cols := b.cols, w := b.w, x := 0
    while (x < w) {
        o := x * 4
        a := NumGet(p, o1 + o, "UInt"), q := NumGet(p, o2 + o, "UInt"), c := NumGet(p, o3 + o, "UInt")
        ar := (a >> 16) & 255, qr := (q >> 16) & 255, cr := (c >> 16) & 255
        mr := ar > qr ? (qr > cr ? qr : (ar > cr ? cr : ar)) : (ar > cr ? ar : (qr > cr ? cr : qr))
        ag := (a >> 8) & 255, qg := (q >> 8) & 255, cg := (c >> 8) & 255
        mg := ag > qg ? (qg > cg ? qg : (ag > cg ? cg : ag)) : (ag > cg ? ag : (qg > cg ? cg : qg))
        ab := a & 255, qb := q & 255, cb := c & 255
        mb := ab > qb ? (qb > cb ? qb : (ab > cb ? cb : ab)) : (ab > cb ? ab : (qb > cb ? cb : qb))
        NumPut("UInt", (mr << 16) | (mg << 8) | mb, cols, o)
        x++
    }
}

; Largest per-channel difference between two 0xRRGGBB colours.
ColDist(a, b) {
    return Max(Abs(((a >> 16) & 255) - ((b >> 16) & 255)), Abs(((a >> 8) & 255) - ((b >> 8) & 255)), Abs((a & 255) - (b & 255)))
}

;------------------------------------------------------------------------------
; Rod profiles
;------------------------------------------------------------------------------
NewProfile(name, track, bar, fish, barW := 0) {
    global ProfSeq
    ProfSeq++
    p := FillProfile({id: "p" ProfSeq, name: name, track: track, bar: bar, fish: fish, barW: barW})
    ResetLut(p)
    return p
}

; Gives a look every field the rest of the macro expects. Looks read back
; from the settings file, and the stand-ins built to test library colours,
; are made this way too, so a look saved by an older version can't arrive
; missing something.
FillProfile(p) {
    for k, v in Map("id", "", "name", "Rod", "track", [], "bar", [], "fish", [], "barW", 0
        , "tolT", 24, "tolB", 24, "tolF", 22, "edgeT", "", "edgeB", "", "sovereign", 0
        , "reels", 0, "lib", "", "used", 0, "relearn", false, "greenBar", false, "probe", false, "kind", "", "capRow", 0, "notes", false, "boxRow", 0, "boxMiss", 0, "boxPrevT", 0, "boxH", 0, "zoneRow", 0, "trkT", 0, "trkB", 0, "minSwitch", 0)
        if !p.HasOwnProp(k)
            p.%k% := v
    return p
}

ResetLut(p) {
    p.lut := Buffer(32768, 255)
}

; Class of one 15-bit colour key: 1 track, 2 bar, 3 fish, 0 anything else.
; The nearest palette colour wins, within that palette's tolerance.
ClassifyKey(p, k) {
    r := ((k >> 10) & 31) * 8 + 4, g := ((k >> 5) & 31) * 8 + 4, b := (k & 31) * 8 + 4
    ; a green-zone rod (Verdant Oath): green inside the bar is still bar
    if (p.greenBar && IsGreen(r, g, b)) {
        NumPut("UChar", 2, p.lut, k)
        return 2
    }
    best := 0, bd := 999
    for cls, list in [p.track, p.bar, p.fish] {
        tol := cls = 1 ? p.tolT : cls = 2 ? p.tolB : p.tolF
        for c in list {
            d := Max(Abs(((c >> 16) & 255) - r), Abs(((c >> 8) & 255) - g), Abs((c & 255) - b))
            if (d <= tol && d < bd)
                bd := d, best := cls
        }
    }
    NumPut("UChar", best, p.lut, k)
    return best
}

; Labels every column, then finds the bar (the biggest block of bar colour,
; allowing small gaps where the fish or an outline covers it) and the fish
; (fish colour anywhere, a gap inside the bar, or an odd colour outside it).
; predFish, when known, breaks ties toward where the fish was.
VisionScan(b, p, predFish := -1) {
    if (p.kind = "box")
        return BoxScan(b, b.geo, predFish, p)
    if (p.kind = "caps")
        return CapScan(b, b.geo, predFish, p)
    if (p.kind = "lite")
        return LiteScan(b, b.geo, predFish, p)
    if (p.kind = "teal")
        return TealScan(b, b.geo, predFish, p)
    if (p.kind = "wood")
        return WoodScan(b, b.geo, predFish, p)
    if (p.kind = "sun")
        return SunScan(b, b.geo, predFish, p)
    w := b.w, cols := b.cols, lab := b.lab, lut := p.lut, covered := 0, x := 0
    while (x < w) {
        c := NumGet(cols, x * 4, "UInt")
        k := ((c >> 9) & 0x7C00) | ((c >> 6) & 0x3E0) | ((c >> 3) & 0x1F)
        l := NumGet(lut, k, "UChar")
        if (l = 255)
            l := ClassifyKey(p, k)
        NumPut("UChar", l, lab, x)
        covered += (l != 0)
        x++
    }
    gapMax := Max(4, Round(w * 0.045))
    bestN := 0, bl := -1, br := -1, cs := -1, cl := -1, cn := 0, x := 0
    while (x < w) {
        if (NumGet(lab, x, "UChar") = 2) {
            if (cs >= 0 && x - cl - 1 > gapMax) {
                if (cn > bestN)
                    bestN := cn, bl := cs, br := cl
                cs := -1
            }
            if (cs < 0)
                cs := x, cn := 0
            cl := x, cn++
        }
        x++
    }
    if (cs >= 0 && cn > bestN)
        bestN := cn, bl := cs, br := cl
    bar := bestN >= Max(3, w * 0.02)
    ; fish candidates
    ; Unknown colours off the bar may be the fish, except while probing a
    ; built-in style: it knows no track colours yet, so unknown means track.
    uf := !p.probe
    maxF := Max(3, Round(w * 0.12)), fx := -1, fBest := -1e9, rs := -1, fishN := 0, fishCol := false, x := 0
    while (x <= w) {
        isF := false
        if (x < w) {
            l := NumGet(lab, x, "UChar")
            inBar := bar && x > bl && x < br
            isF := (l = 3) || (inBar && l != 2) || (uf && !inBar && l = 0 && !(bar && x >= bl - 2 && x <= br + 2))
        }
        if isF {
            if (rs < 0)
                rs := x, fishN := 0
            fishN += (NumGet(lab, x, "UChar") = 3)
        } else if (rs >= 0) {
            len := x - rs
            if (len <= maxF) {
                cen := rs + (len - 1) / 2
                inside := bar && cen > bl && cen < br
                sc := 4 * fishN + (inside ? 2 : 1) * len
                if (predFish >= 0)
                    sc -= Abs(cen - predFish) / Max(1, w * 0.08)
                if (sc > fBest)
                    fBest := sc, fx := cen, fishCol := fishN > 0
            }
            rs := -1
        }
        x++
    }
    return {bar: bar, bl: bl, br: br, fish: fx >= 0, fx: fx, cover: covered / w, n: bestN, fishCol: fishCol}
}

; Fraction of sampled columns with a sharp brightness change across a row.
EdgeStrength(b, row) {
    if (row < 1 || row >= b.h - 1)
        return 0
    p := b.bits, s := b.stride, up := (row - 1) * s, dn := (row + 1) * s
    n := 0, hit := 0, x := 2, w := b.w - 2
    while (x < w) {
        c := NumGet(p, up + x * 4, "UInt"), d := NumGet(p, dn + x * 4, "UInt")
        l1 := ((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)
        l2 := ((d >> 16) & 255) * 2 + ((d >> 8) & 255) * 5 + (d & 255)
        hit += (Abs(l1 - l2) >= 150)
        n++, x += 5
    }
    return n ? hit / n : 0
}

; Strongest horizontal edge above and below the track, if both are clear.
FindEdges(b, geo) {
    bt := 0, st := 0, bb := 0, sb := 0
    r := 1
    while (r <= geo.m + 2) {
        s := EdgeStrength(b, r)
        if (s > st)
            st := s, bt := r
        r++
    }
    r := geo.m + geo.ih - 2
    while (r <= b.h - 2) {
        s := EdgeStrength(b, r)
        if (s > sb)
            sb := s, bb := r
        r++
    }
    return {top: bt, bot: bb, st: st, sb: sb, ok: st >= 0.45 && sb >= 0.45}
}

; Is the learned track outline still there? Checks the stored rows +-1.
EdgesPresent(b, geo, p) {
    if (p.edgeT = "")
        return -1
    t := geo.m + Round(p.edgeT * geo.ih), d := geo.m + geo.ih + Round(p.edgeB * geo.ih)
    st := Max(EdgeStrength(b, t - 1), EdgeStrength(b, t), EdgeStrength(b, t + 1))
    sb := Max(EdgeStrength(b, d - 1), EdgeStrength(b, d), EdgeStrength(b, d + 1))
    return (st >= 0.3 && sb >= 0.3) ? 1 : 0
}

RememberEdges(p, e, geo) {
    p.edgeT := Round((e.top - geo.m) / geo.ih, 3), p.edgeB := Round((e.bot - geo.m - geo.ih) / geo.ih, 3)
    SaveRodProfile(p)
}

;------------------------------------------------------------------------------
; Learning a new look
;------------------------------------------------------------------------------
; Greedy colour clustering. Returns the mean of every cluster holding at
; least minShare of the samples, largest first (at most `most`).
VClusters(colors, radius, minShare, most := 6) {
    cl := []
    for c in colors {
        r := (c >> 16) & 255, g := (c >> 8) & 255, b := c & 255, hit := 0
        for k in cl {
            if (Abs(k.r - r) <= radius && Abs(k.g - g) <= radius && Abs(k.b - b) <= radius) {
                hit := k
                break
            }
        }
        if !hit {
            if (cl.Length >= 16)
                continue
            hit := {r: r, g: g, b: b, sr: 0, sg: 0, sb: 0, n: 0}
            cl.Push(hit)
        }
        hit.sr += r, hit.sg += g, hit.sb += b, hit.n++
        hit.r := hit.sr // hit.n, hit.g := hit.sg // hit.n, hit.b := hit.sb // hit.n
    }
    total := Max(1, colors.Length), keep := []
    for k in cl
        if (k.n >= total * minShare)
            keep.Push(k)
    ; largest first
    Loop keep.Length - 1 {
        i := A_Index
        Loop keep.Length - i {
            j := A_Index
            if (keep[j].n < keep[j + 1].n)
                t := keep[j], keep[j] := keep[j + 1], keep[j + 1] := t
        }
    }
    out := []
    for k in keep {
        if (out.Length >= most)
            break
        out.Push((k.r << 16) | (k.g << 8) | k.b)
    }
    return out
}

; Finds the bar from two frames between which it moved: the shift that
; explains the most changed columns is the bar's movement, and the columns
; it explains are the bar's leading and trailing strips (or all of a
; patterned bar). Returns {bl, br, dx} for frame 1, or 0.
FindMovedBar(c0, c1, w) {
    ch := [], x := 0
    while (x < w) {
        if (ColDist(NumGet(c1, x * 4, "UInt"), NumGet(c0, x * 4, "UInt")) > 30)
            ch.Push(x)
        x++
    }
    if (ch.Length < 6)
        return 0
    ; The shift is scored over every column in the changed span, changed or
    ; not. Shifted too far, the bar maps its own columns onto old track;
    ; too little, its leading strip goes unexplained. So the true shift is
    ; the one lowest cost, on flat bars and gradients alike. Distances are
    ; capped so the fish, which moves on its own, can't dominate.
    a := ch[1], z := ch[ch.Length], span := z - a + 1
    maxDx := Min(120, w // 3), bestDx := 0, bestCost := 1e9, dx := -maxDx
    while (dx <= maxDx) {
        if (Abs(dx) >= 3) {
            sum := 0, n := 0, x := a
            while (x <= z) {
                xs := x - dx
                if (xs >= 0 && xs < w) {
                    u := NumGet(c1, x * 4, "UInt"), v := NumGet(c0, xs * 4, "UInt")
                    e := Max(Abs(((u >> 16) & 255) - ((v >> 16) & 255)), Abs(((u >> 8) & 255) - ((v >> 8) & 255)), Abs((u & 255) - (v & 255)))
                    sum += e < 60 ? e : 60, n++
                }
                x++
            }
            if (n >= span * 0.6) {
                c := sum / n
                if (c < bestCost - 1e-9 || (Abs(c - bestCost) <= 1e-9 && Abs(dx) < Abs(bestDx)))
                    bestCost := c, bestDx := dx
            }
        }
        dx++
    }
    if !bestDx
        return 0
    if (bestCost > 20)
        return 0
    ; The track just outside the changed span, on each side.
    tl := MedianColor(c1, a - 16, a - 4, w), tr := MedianColor(c1, z + 4, z + 16, w)
    if (tl < 0)
        tl := tr
    if (tr < 0)
        tr := tl
    if (tl < 0)
        return 0
    ; A bar column now is not track-coloured and holds what sat one shift
    ; back. That excludes the strip the bar vacated (track now) and usually
    ; the fish (it moves on its own); the longest such run, bridging gaps
    ; up to a fish's width, is the bar.
    fishMax := Max(4, Round(w * 0.025)), bl := -1, br := -1, rs := -1, rl := -99
    x := Max(0, a - 20), xe := Min(w - 1, z + 20)
    while (x <= xe) {
        c := NumGet(c1, x * 4, "UInt")
        isBar := ColDist(c, tl) > 24 && ColDist(c, tr) > 24
        if isBar {
            xs := x - bestDx
            if (xs >= 0 && xs < w)
                isBar := ColDist(c, NumGet(c0, xs * 4, "UInt")) <= 20
        }
        if isBar {
            if (rs >= 0 && x - rl - 1 > fishMax) {
                if (rl - rs > br - bl)
                    bl := rs, br := rl
                rs := -1
            }
            if (rs < 0)
                rs := x
            rl := x
        }
        x++
    }
    if (rs >= 0 && rl - rs > br - bl)
        bl := rs, br := rl
    if (bl < 0)
        return 0
    bw := br - bl + 1
    if (bw < w * 0.03 || bw > w * 0.85)
        return 0
    return {bl: bl, br: br, dx: bestDx, lo: a, hi: z, n: bw, ch: ch.Length, tl: tl, tr: tr, cost: Round(bestCost, 1)}
}

; The median of the packed colours in columns x0..x1 (clipped), or -1.
MedianColor(cols, x0, x1, w) {
    v := []
    x := Max(0, x0)
    while (x <= Min(w - 1, x1))
        v.Push(NumGet(cols, x * 4, "UInt") & 0xFFFFFF), x++
    if !v.Length
        return -1
    s := ""
    for c in v
        s .= c "`n"
    s := Sort(RTrim(s, "`n"), "N")
    return Integer(StrSplit(s, "`n")[(v.Length + 1) // 2])
}

; True when the colours just outside the found bar are the track's, on
; each side that isn't the end of the track. The check looks past a fish's
; width, so a fish resting against the edge doesn't fail it; a bar learned
; from only part of a gradient does, since past its edge the bar goes on.
BordersTrack(cols, w, bl, br, tl, tr) {
    reach := 5 + Max(4, Round(w * 0.025))
    for side in [-1, 1] {
        e := side < 0 ? bl : br, ref := side < 0 ? tl : tr
        if (side < 0 ? e <= 5 : e >= w - 6)
            continue
        n := 0, good := 0, k := 2
        while (k <= reach) {
            x := e + side * k
            if (x < 0 || x >= w)
                break
            n++, good += ColDist(NumGet(cols, x * 4, "UInt"), ref) <= 30
            k++
        }
        if (n >= 4 ? good < 4 : good < n)
            return false
    }
    return true
}

; Builds a profile from a frame where the bar is known to span [bl, br]:
; bar colours from inside, track colours from outside, and fish colours
; from narrow runs that fit neither.
ProfileFromFrame(cols, w, bl, br, name := "") {
    inside := [], outside := []
    Loop w {
        x := A_Index - 1, c := NumGet(cols, x * 4, "UInt")
        if (x >= bl && x <= br)
            inside.Push(c)
        else if (x < bl - 2 || x > br + 2)
            outside.Push(c)
    }
    barPal := VClusters(inside, 18, 0.08, 6)
    trackPal := VClusters(outside, 18, 0.10, 5)
    if (!barPal.Length || !trackPal.Length)
        return 0
    ; Odd columns fit neither palette: the fish, if it is narrow. Inside the
    ; bar, anything that isn't bar colour counts, even if it matches the
    ; track: a dark fish on a dark track still stands out against the bar
    ; it sits on, and without its colour it would vanish once it left the bar.
    odd := [], runs := [], x := 0, rs := -1
    while (x <= w) {
        isOdd := false
        if (x < w) {
            c := NumGet(cols, x * 4, "UInt"), isOdd := true
            if (x < bl || x > br)
                for t in trackPal
                    if (ColDist(c, t) <= 26) {
                        isOdd := false
                        break
                    }
            if isOdd
                for t in barPal
                    if (ColDist(c, t) <= 26) {
                        isOdd := false
                        break
                    }
        }
        if isOdd {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            if (x - rs <= w * 0.12 && !(x - rs <= 2 && (Abs(rs - bl) <= 2 || Abs(x - 1 - br) <= 2))) {
                rc := []
                Loop x - rs
                    c := NumGet(cols, (rs + A_Index - 1) * 4, "UInt"), odd.Push(c), rc.Push(c)
                runs.Push({x0: rs, x1: x - 1, cols: rc})
            }
            rs := -1
        }
        x++
    }
    ; Artwork printed on the bar (the arrows near each end of Fisch's bar)
    ; shows up in two or more separate places inside it, in the same colour;
    ; the fish is a single marker. Such colours join the bar's palette and
    ; are dropped from the fish's, so the arrows read as bar: the bar stays
    ; one piece and the fish can't be mistaken for an arrow.
    decor := [], inside := []
    for r in runs
        if (r.x0 >= bl && r.x1 <= br)
            inside.Push(VClusters(r.cols, 16, 0.15, 3))
    for i, ci in inside
        for c in ci
            for j, cj in inside
                if (j != i)
                    for c2 in cj
                        if (ColDist(c, c2) <= 30) {
                            decor.Push(c)
                            break 2
                        }
    if decor.Length {
        for c in decor {
            have := false
            for bc in barPal
                have := have || ColDist(c, bc) <= 18
            if !have
                barPal.Push(c)
        }
        keep := []
        for c in odd {
            art := false
            for dc in decor
                art := art || ColDist(c, dc) <= 30
            if !art
                keep.Push(c)
        }
        odd := keep
    }
    fishPal := odd.Length ? VClusters(odd, 16, 0.2, 3) : []
    ; Fish colours close to the track are kept only when the fish has none of
    ; its own: they rescue a dark fish on a dark track, but for an outlined
    ; fish they would make plain track read as fish.
    own := [], near := []
    for f in fishPal {
        isNear := false
        for t in trackPal
            if (ColDist(f, t) <= 26) {
                isNear := true
                break
            }
        (isNear ? near : own).Push(f)
    }
    if own.Length
        fishPal := own
    p := NewProfile(name != "" ? name : NextRodName(barPal, fishPal), trackPal, barPal, fishPal, (br - bl + 1) / w)
    p.lib := LibMatch(barPal, fishPal)
    if (p.lib != "" && name = "")
        p.name := RodById(p.lib).name
    return p
}

; Learns a new look while the reel is up: holds the mouse until the bar has
; visibly moved (or releases if it is pinned right), then learns from the
; two frames. Returns {prof, d} or 0. The mouse is left released.
LearnLook(b, geo, &trace := "") {
    VisionGrab(b, geo)
    c0 := Buffer(b.w * 4)
    DllCall("RtlMoveMemory", "Ptr", c0, "Ptr", b.cols, "UPtr", b.w * 4)
    held := true
    Click("Down")
    t0 := A_TickCount, mv := 0, prev := 0, ok := false
    loop {
        FineSleep(12)
        VisionGrab(b, geo)
        mv := FindMovedBar(c0, b.cols, b.w)
        ; A find counts once the next frame agrees: same width, and moved on
        ; by exactly the extra shift. One-off mistakes rarely repeat.
        if (mv && Abs(mv.dx) >= 10) {
            if (prev && Abs((mv.br - mv.bl) - (prev.br - prev.bl)) <= 3 && Abs((mv.bl - prev.bl) - (mv.dx - prev.dx)) <= 3) {
                ok := true
                break
            }
            prev := mv
        } else {
            prev := 0
        }
        if (A_TickCount - t0 > 420) {
            if !held
                break
            ; nothing confirmed while holding: the bar may be pinned right, so release
            Click("Up")
            held := false
            DllCall("RtlMoveMemory", "Ptr", c0, "Ptr", b.cols, "UPtr", b.w * 4)
            t0 := A_TickCount, prev := 0
        }
    }
    if held
        Click("Up")
    if !ok {
        trace := mv ? "the bar's position didn't hold steady between frames" : "no block moved with the bar"
        return 0
    }
    if !BordersTrack(b.cols, b.w, mv.bl, mv.br, mv.tl, mv.tr) {
        trace := Format("check failed (bar {}-{} doesn't meet the track at both edges, shift {})", mv.bl, mv.br, mv.dx)
        return 0
    }
    p := ProfileFromFrame(b.cols, b.w, mv.bl, mv.br)
    if !p {
        trace := "colours could not be separated"
        return 0
    }
    d := VisionScan(b, p)
    if (!d.bar || Abs(d.bl - mv.bl) > 6 || Abs(d.br - mv.br) > 6 || d.cover < 0.8) {
        trace := Format("check failed (bar {} {}-{} vs {}-{}, cover {:.2f}, shift {}, span {}-{})"
            , d.bar, d.bl, d.br, mv.bl, mv.br, d.cover, mv.dx, mv.lo, mv.hi)
        return 0
    }
    trace := Format("learned: bar {}-{}, moved {} px (span {}-{}, cost {})", mv.bl, mv.br, mv.dx, mv.lo, mv.hi, mv.cost)
    return {prof: p, d: d}
}

; Tries the known looks, most recent first. A look matches when most of the
; row fits its palettes and the bar is found at a plausible width.
MatchProfile(b, geo) {
    for p in RodProfiles {
        FillProfile(p)          ; a look from another version may lack a field
        d := VisionScan(b, p)
        if (!d.bar || d.cover < 0.8)
            continue
        if (p.barW > 0 && Abs((d.br - d.bl + 1) / b.w - p.barW) > Max(0.04, p.barW * 0.3))
            continue
        if (EdgesPresent(b, geo, p) = 0)
            continue
        return {prof: p, d: d}
    }
    return 0
}

; Library looks (rods with their own reel colours) seed a full profile the
; first time they are seen.
; One built-in reel style against the reel: its own bar and fish colours
; must show, then the track's colours are taken from this frame so the reel
; can be told from scenery. Nothing here is saved.
ProbeLib(b, lib) {
    w := b.w, bars := [], fishes := []
    for h in lib.bar
        bars.Push(Integer("0x" h))
    for h in lib.fish
        fishes.Push(Integer("0x" h))
    green := lib.HasOwnProp("greenBar") && lib.greenBar
    if (lib.HasOwnProp("kind") && lib.kind = "wood") {
        ; Verdant Oath (see WoodScan)
        q := {barW: 0, boxPrev: -1}
        d := WoodScan(b, b.geo, -1, q)
        if !(d.bar && d.fish)
            return 0
        p := FillProfile({name: CurRodName != "" ? CurRodName : lib.name, lib: lib.id, kind: "wood", greenBar: true
            , barW: (d.br - d.bl + 1) / b.w, id: "rod:" (CurRodName != "" ? CurRodName : lib.id)})
        ResetLut(p)
        return {prof: p, d: d}
    }
    if (lib.HasOwnProp("kind") && (lib.kind = "teal" || lib.kind = "sun")) {
        ; Requiem and Apollo's Sunshot (see TealScan, SunScan)
        q := {barW: 0, boxPrev: -1}
        d := lib.kind = "sun" ? SunScan(b, b.geo, -1, q) : TealScan(b, b.geo, -1, q)
        if !(d.bar && d.fish)
            return 0
        p := FillProfile({name: CurRodName != "" ? CurRodName : lib.name, lib: lib.id, kind: lib.kind
            , barW: (d.br - d.bl + 1) / b.w, id: "rod:" (CurRodName != "" ? CurRodName : lib.id)
            , minSwitch: lib.HasOwnProp("minSwitch") ? lib.minSwitch : 0})
        ResetLut(p)
        return {prof: p, d: d}
    }
    if (lib.HasOwnProp("kind") && lib.kind = "lite") {
        ; Pinion's Aria without a skin (see LiteScan)
        q := {trkT: 0, trkB: 0, barW: 0}
        d := LiteScan(b, b.geo, -1, q)
        if !(d.bar && d.fish)
            return 0
        p := FillProfile({name: CurRodName != "" ? CurRodName : lib.name, lib: lib.id, kind: "lite"
            , barW: (d.br - d.bl + 1) / b.w, id: "rod:" (CurRodName != "" ? CurRodName : lib.id)
            , trkT: q.trkT, trkB: q.trkB, notes: true})
        ResetLut(p)
        return {prof: p, d: d}
    }
    if (lib.HasOwnProp("kind") && (lib.kind = "box" || lib.kind = "caps")) {
        ; read by shape (BoxScan, CapScan): no colours to match
        q := {capRow: lib.kind = "caps" ? CapRow(b, b.geo) : 0, barW: 0, boxRow: 0, boxMiss: 0}
        d := lib.kind = "box" ? BoxScan(b, b.geo, -1, q) : CapScan(b, b.geo, -1, q)
        if !(d.bar && d.fish)            ; both: straight lines in scenery (dock planks) can pass for a bar
            return 0
        p := FillProfile({name: CurRodName != "" ? CurRodName : lib.name, lib: lib.id, kind: lib.kind
            , barW: (d.br - d.bl + 1) / b.w, id: "rod:" (CurRodName != "" ? CurRodName : lib.id)
            , capRow: q.capRow, boxRow: q.boxRow, notes: lib.HasOwnProp("notes") && lib.notes})
        ResetLut(p)
        return {prof: p, d: d}
    }
    probe := FillProfile({name: lib.name, bar: bars, fish: fishes, tolB: lib.bt + 6, tolF: lib.ft + 6, greenBar: green, probe: true})
    ResetLut(probe)
    d := VisionScan(b, probe)
    ; the rod's own fish colour, and mostly its own bar colours
    if !(d.bar && d.fish && d.fishCol && d.n >= 0.6 * (d.br - d.bl + 1))
        return 0
    bw := (d.br - d.bl + 1) / w
    if (bw < 0.03 || bw > 0.85)
        return 0
    p := ProfileFromFrame(b.cols, w, d.bl, d.br, lib.name)
    if !p
        return 0
    ; the style's own colours plus the exact shades on screen (kept in memory only)
    for h in bars
        p.bar.InsertAt(1, h)
    for f in fishes
        p.fish.Push(f)
    p.lib := lib.id, p.greenBar := green
    p.id := "rod:" (CurRodName != "" ? CurRodName : lib.id)
    p.name := CurRodName != "" ? CurRodName : lib.name
    ResetLut(p)
    d2 := VisionScan(b, p)
    return (d2.bar && d2.cover >= 0.75) ? {prof: p, d: d2} : 0
}

MatchLibrary(b) {
    for lib in RodLib
        if (r := ProbeLib(b, lib))
            return r
    return 0
}

; The reel style for this reel. The rod name read from the hotbar picks it;
; if that isn't known, every built-in style is tried and the best fit wins.
; The chosen style is kept for this session only (never saved), so the next
; reel is recognized at once.
MatchPrecoded(b, geo) {
    ids := []
    if (CurRodLib != "") {
        ids.Push(CurRodLib)
        for l in RodLib
            if (l.HasOwnProp("alias") && l.alias = CurRodLib)
                ids.Push(l.id)                 ; the same rod's other look
    }
    else
        for lib in RodLib
            ids.Push(lib.id)
    best := 0, bestScore := 0, bestId := ""
    for id in ids {
        if SessionLooks.Has(id) {
            p := FillProfile(SessionLooks[id])
            d := VisionScan(b, p)
            if (d.bar && d.cover >= 0.75 && (p.kind != "" || EdgesPresent(b, geo, p) != 0)) {
                sc := d.cover + (d.fish ? 0.2 : 0)
                if (sc > bestScore)
                    best := {prof: p, d: d}, bestScore := sc, bestId := id
                continue
            }
        }
        lib := 0
        for l in RodLib
            if (l.id = id)
                lib := l
        if (lib && (r := ProbeLib(b, lib))) {
            sc := r.d.cover + (r.d.fish ? 0.2 : 0)
            if (sc > bestScore)
                best := r, bestScore := sc, bestId := id
        }
    }
    if best
        SessionLooks[bestId] := best.prof
    return best
}

IsGreen(r, g, b) => g >= r + 30 && g >= b + 15 && g >= 70

; The centre column of the green zone inside the found bar, or -1.
GreenZone(b, d) {
    best := 0, bs := -1, rs := -1, x := d.bl
    while (x <= d.br + 1) {
        on := false
        if (x <= d.br) {
            c := NumGet(b.cols, x * 4, "UInt")
            on := IsGreen((c >> 16) & 255, (c >> 8) & 255, c & 255)
        }
        if on {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            if (x - rs > best)
                best := x - rs, bs := rs
            rs := -1
        }
        x++
    }
    return best >= 3 ? bs + (best - 1) / 2 : -1
}

LibMatch(barPal, fishPal) {
    for lib in RodLib {
        ok := false
        for h in lib.bar {
            for c in barPal
                if (ColDist(Integer("0x" h), c) <= 16)
                    ok := true
        }
        if (!ok || !fishPal.Length)     ; a library name needs its fish colour too
            continue
        for h in lib.fish
            for c in fishPal
                if (ColDist(Integer("0x" h), c) <= 18)
                    return lib.id
    }
    return ""
}

NextRodName(barPal, fishPal) {
    n := 1
    for p in RodProfiles
        if RegExMatch(p.name, "^Rod look (\d+)$", &m)
            n := Max(n, m[1] + 1)
    return "Rod look " n
}

; Adds a newly learned look, or refreshes a look it duplicates.
AdoptProfile(p) {
    FillProfile(p)
    for q in RodProfiles {
        if (q.id = p.id)
            return q
        same := true
        for c in p.bar {
            hit := false
            for d in q.bar
                if (ColDist(c, d) <= 14)
                    hit := true
            if !hit {
                same := false
                break
            }
        }
        if (same && Abs(q.barW - p.barW) <= 0.03 && p.bar.Length) {
            q.track := p.track, q.fish := p.fish.Length ? p.fish : q.fish, q.barW := p.barW
            ResetLut(q)
            SaveRodProfile(q)
            return q
        }
    }
    RodProfiles.InsertAt(1, p)
    SaveRodProfile(p)
    return p
}

TouchProfile(p) {
    for i, q in RodProfiles
        if (q = p) {
            if (i > 1)
                RodProfiles.RemoveAt(i), RodProfiles.InsertAt(1, p)
            break
        }
}

ProfById(id) {
    for p in RodProfiles
        if (p.id = id)
            return p
    return 0
}

;------------------------------------------------------------------------------
; Storage: [Looks] in FischMacro.ini, one line per look.
;   p3=Halibut Harpoon|0.380|1B2733,1C2834|5D52A8|0D0B0B|-0.150|0.080|0|12|halibut
;------------------------------------------------------------------------------
LoadRodProfiles() {
    global ProfSeq
    try section := IniRead(IniPath, "Looks")
    catch
        return
    Loop Parse, section, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^(p\d+)=(.*)$", &m)
            continue
        f := StrSplit(m[2], "|")
        if (f.Length < 10)
            continue
        p := FillProfile({id: m[1], name: f[1], barW: f[2] + 0, track: HexList(f[3]), bar: HexList(f[4]), fish: HexList(f[5])
            , edgeT: f[6] = "" ? "" : f[6] + 0, edgeB: f[7] = "" ? "" : f[7] + 0, sovereign: f[8] + 0
            , reels: f[9] + 0, lib: f[10]})
        ; Looks saved before bar artwork was handled may have learned an
        ; arrow as the fish: learn their colours again on the next reel.
        p.relearn := f.Length < 11 || (f[11] + 0) < LOOK_FORMAT
        if (!p.track.Length || !p.bar.Length)
            continue
        ResetLut(p)
        RodProfiles.Push(p)
        ProfSeq := Max(ProfSeq, SubStr(p.id, 2) + 0)
    }
}

SaveRodProfile(p) => 0            ; reel styles are built in; nothing about rods is saved

ForgetProfile(p) {
    for i, q in RodProfiles
        if (q = p) {
            RodProfiles.RemoveAt(i)
            break
        }
    if !NoSave
        try IniDelete(IniPath, "Looks", p.id)
}

HexList(s) {
    out := []
    for h in StrSplit(s, ",")
        if RegExMatch(h, "i)^[0-9a-f]{6}$")
            out.Push(Integer("0x" h))
    return out
}

HexJoin(list) {
    s := ""
    for c in list
        s .= (s = "" ? "" : ",") Format("{:06X}", c)
    return s
}

;------------------------------------------------------------------------------
; Teaching a look by hand from a frozen frame: the user clicks the bar and
; the fish. The bar's extent is grown from the click along the track row.
;------------------------------------------------------------------------------
TeachLook(b, geo, barX, fishX) {
    cols := b.cols, w := b.w
    barX := Clamp(barX, 0, w - 1), fishX := Clamp(fishX, 0, w - 1)
    ref := NumGet(cols, barX * 4, "UInt"), bl := barX, br := barX
    ; grow while colours stay close to the bar's running range
    while (bl > 0 && ColDist(NumGet(cols, (bl - 1) * 4, "UInt"), ref) <= 40)
        bl--
    while (br < w - 1 && ColDist(NumGet(cols, (br + 1) * 4, "UInt"), ref) <= 40)
        br++
    if (fishX >= bl && fishX <= br) {
        ; the fish sits inside the bar: bridge across it
        l := bl, r := br
        while (r < w - 1 && ColDist(NumGet(cols, (r + 1) * 4, "UInt"), ref) > 40 && r - fishX < w * 0.06)
            r++
        while (r < w - 1 && ColDist(NumGet(cols, (r + 1) * 4, "UInt"), ref) <= 40)
            r++
        br := Max(br, r)
    }
    if ((br - bl + 1) < w * 0.03)
        return 0
    p := ProfileFromFrame(cols, w, bl, br)
    if !p
        return 0
    fc := []
    Loop 5 {
        x := Clamp(fishX + A_Index - 3, 0, w - 1)
        fc.Push(NumGet(cols, x * 4, "UInt"))
    }
    for c in VClusters(fc, 14, 0.2, 2)
        p.fish.Push(c)
    ResetLut(p)
    p.name := "Taught " p.name
    return p
}

; A picture of what the macro sees, for the Live tab and snapshots: the band
; itself, then a strip showing each column's class (dark: other, grey: track,
; white: bar, light grey: fish), with the bar outlined and the fish marked by
; a dashed line. mono draws the band in greys for the black-and-white theme.
; Everything is drawn with native fills, so it costs about a millisecond.
; Returns an HBITMAP the caller must delete.
VisionPicture(b, d, dw, dh, mono := false) {
    static br := 0
    if !br {
        br := Map()
        for name, c in Map("other", 0x303030, "track", 0x6E6E6E, "bar", 0xFFFFFF, "fish", 0xB4B4B4, "white", 0xFFFFFF, "black", 0x000000, "none", 0x161616)
            br[name] := DllCall("CreateSolidBrush", "UInt", c, "Ptr")
    }
    dw := Max(16, dw), dh := Max(24, dh)
    stripH := 12, bandH := dh - stripH - 2
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", dw, bi, 4), NumPut("Int", -dh, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
    old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    rc := Buffer(16)
    R(x1, y1, x2, y2, brush) {
        NumPut("Int", x1, "Int", y1, "Int", x2, "Int", y2, rc)
        DllCall("FillRect", "Ptr", mdc, "Ptr", rc, "Ptr", brush)
    }
    R(0, 0, dw, dh, br["black"])
    if mono {
        ; An 8-bit grey-palette copy turns the band grey in one native call.
        gi := Buffer(40 + 1024, 0)
        NumPut("UInt", 40, gi, 0), NumPut("Int", dw, gi, 4), NumPut("Int", -bandH, gi, 8)
        NumPut("UShort", 1, gi, 12), NumPut("UShort", 8, gi, 14), NumPut("UInt", 256, gi, 32)
        Loop 256
            NumPut("UInt", (A_Index - 1) * 0x010101, gi, 36 + A_Index * 4)
        gdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
        gbm := DllCall("CreateDIBSection", "Ptr", gdc, "Ptr", gi, "UInt", 0, "Ptr*", &gbits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        gold := DllCall("SelectObject", "Ptr", gdc, "Ptr", gbm, "Ptr")
        DllCall("SetStretchBltMode", "Ptr", gdc, "Int", 3)
        DllCall("StretchBlt", "Ptr", gdc, "Int", 0, "Int", 0, "Int", dw, "Int", bandH
            , "Ptr", b.dc, "Int", 0, "Int", 0, "Int", b.w, "Int", b.h, "UInt", 0x00CC0020)
        DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", dw, "Int", bandH, "Ptr", gdc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        DllCall("SelectObject", "Ptr", gdc, "Ptr", gold)
        DllCall("DeleteObject", "Ptr", gbm)
        DllCall("DeleteDC", "Ptr", gdc)
    } else {
        DllCall("SetStretchBltMode", "Ptr", mdc, "Int", 3)
        DllCall("StretchBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", dw, "Int", bandH
            , "Ptr", b.dc, "Int", 0, "Int", 0, "Int", b.w, "Int", b.h, "UInt", 0x00CC0020)
    }
    y0 := bandH + 2
    if IsObject(d) {
        names := ["other", "track", "bar", "fish"]
        x := 0
        while (x < dw) {
            c := NumGet(b.lab, Min(b.w - 1, x * b.w // dw), "UChar")
            x2 := x + 1
            while (x2 < dw && NumGet(b.lab, Min(b.w - 1, x2 * b.w // dw), "UChar") = c)
                x2++
            R(x, y0, x2, y0 + stripH, br[names[(c > 3 ? 0 : c) + 1]])
            x := x2
        }
        if d.bar {
            x1 := d.bl * dw // b.w, x2 := (d.br + 1) * dw // b.w
            for e in [[x1, 0, x2, 2], [x1, bandH - 2, x2, bandH], [x1, 0, x1 + 2, bandH], [x2 - 2, 0, x2, bandH]]
                R(e[1], e[2], e[3], e[4], br["white"])
            for e in [[x1 + 2, 2, x2 - 2, 3], [x1 + 2, bandH - 3, x2 - 2, bandH - 2], [x1 + 2, 2, x1 + 3, bandH - 2], [x2 - 3, 2, x2 - 2, bandH - 2]]
                R(e[1], e[2], e[3], e[4], br["black"])
        }
        if d.fish {
            fx := Round(d.fx * dw / b.w), y := 0
            while (y < bandH) {
                R(fx - 1, y, fx + 2, Min(bandH, y + 3), br[Mod(y // 3, 2) ? "black" : "white"])
                y += 3
            }
        }
    } else {
        R(0, y0, dw, y0 + stripH, br["none"])
    }
    DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    return hbm
}

; A standalone copy of the band's current image, for saving later.
BandCopy(b) {
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", b.w, bi, 4), NumPut("Int", -b.h, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
    old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", b.w, "Int", b.h, "Ptr", b.dc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    return hbm
}

;------------------------------------------------------------------------------
; Noiseform's reel, read by its shape. Its glow follows the fish and its bar
; turns dark and see-through when the fish leaves it, so colours don't hold.
; What does: the bar is a box whose sides are thin black lines running the
; full height of the reel, and the fish is a black capsule that sticks out
; above and below that box. Measured on a real Noiseform reel.
;------------------------------------------------------------------------------
BoxScan(b, geo, predFish := -1, p := 0, now := -1) {
    global ShapeWhy
    w := b.w, barW := p ? p.barW : 0, minH := Max(12, Round(geo.ih * 0.3))
    now := now >= 0 ? now : A_TickCount / 1000
    ; The bar can't jump across the track between looks: once it's being
    ; followed, only sides near where it just was count. (Zones drawn over
    ; the bar can hide a side, and a still pair of lines elsewhere can be
    ; the right distance apart.)
    near := -1, reach := 0
    if (p && p.HasOwnProp("boxPrev") && p.boxPrev >= 0 && p.HasOwnProp("boxPrevT"))
        near := p.boxPrev, reach := w * (0.04 + Min(1, Max(0, now - p.boxPrevT)))    ; about a track width a second
    ; Dark lines inside a zone's picture, or at the track's own ends, aren't
    ; bar sides (a zone drawn over the bar hides the real side there).
    skip := [[0, w * 0.04], [w * 0.96, w]]
    if (p && p.HasOwnProp("zoneRow") && p.zoneRow)
        for z in FindZones(b, geo, p)
            skip.Push([z.x - w * 0.065, z.x + w * 0.065])
    none := {bar: false, bl: -1, br: -1, fish: false, fx: -1, cover: 0, n: 0, fishCol: false}
    ; the row through the middle of the box: found by searching the band for
    ; the tallest pair of black sides a bar-width apart, then kept (searched
    ; again if it stops working), so it works wherever the reel area sits
    row := (p && p.boxRow) ? p.boxRow : -1, pk := 0
    if (row >= 0)
        pk := BoxPick(b, row, w, minH, barW, near, reach, skip)
    bl := -1, br := -1, top := -1, bot := -1
    if pk
        bl := pk.bl, br := pk.br, top := pk.top, bot := pk.bot
    ; one side hidden (in the dark state a zone can cover it): once the reel
    ; is running, the other side is one bar-width away, near its last place
    if (!pk && row >= 0 && p && barW && p.HasOwnProp("boxPrev") && p.boxPrev >= 0) {  ; (width known)
        bw := barW * w, bestD := Max(w * 0.05, reach)
        for cx in BoxCands(b, row, w, skip) {
            sp := BoxSpan(b, cx, row)
            if (sp[2] - sp[1] < minH)
                continue
            for opt in [[cx, cx + bw], [cx - bw, cx]]
                if (opt[1] >= -2 && opt[2] <= w + 1 && Abs((opt[1] + opt[2]) / 2 - p.boxPrev) < bestD)
                    bestD := Abs((opt[1] + opt[2]) / 2 - p.boxPrev), bl := opt[1], br := opt[2], top := sp[1], bot := sp[2]
        }
    }
    if (bl < 0 && (!p || !p.boxRow || ++p.boxMiss >= 8)) {       ; lost for a while: search anew
        f := BoxFind(b, geo, barW)
        if f {
            pk := f.pk, bl := pk.bl, br := pk.br, top := pk.top, bot := pk.bot
            if p
                p.boxRow := f.row, p.boxMiss := 0
        } else if p
            p.boxMiss := 0
    }
    if (bl < 0)
        ShapeWhy := "no two tall black bar sides a bar-width apart on the reel"
    else if p {
        p.boxMiss := 0
        ; the bar can change size during a reel: the width expected follows
        ; the median of recent readings of both sides
        if (bl >= 0 && br > bl) {
            if !p.HasOwnProp("boxWs")
                p.boxWs := []
            p.boxWs.Push(br - bl)
            if (p.boxWs.Length > 15)
                p.boxWs.RemoveAt(1)
            if (p.boxWs.Length >= 5)
                p.barW := ZMedian(p.boxWs) / w
        }
        if (top >= 0 && bot - top >= minH)
            p.boxH := bot - top
    }
    ; the fish: a black capsule of steady width just above and just below the
    ; box (or the reel area, if the box wasn't found)
    if (top >= 0)
        off := Max(4, Round((bot - top) * 0.12)), yu := top - off, yd := bot + off
    else
        off := Max(3, Round(geo.ih * 0.3)), yu := geo.m - off, yd := geo.m + geo.ih + off
    up := BoxRuns(b, Clamp(yu, 0, b.h - 1), w), dn := BoxRuns(b, Clamp(yd, 0, b.h - 1), w)
    fx := -1, fBest := 1e9, tol := Max(3, Round(w * 0.004))
    for u in up
        for v in dn {
            if (Abs(u[1] - v[1]) > tol || Abs(u[2] - v[2]) > Max(4, 0.6 * Max(u[2], v[2])))
                continue
            cen := (u[1] + v[1]) / 2
            sc := Abs(u[2] - v[2]) + (predFish >= 0 ? Abs(cen - predFish) / Max(1, w * 0.05) : 0)
            if (sc < fBest)
                fBest := sc, fx := cen
        }
    none.fish := fx >= 0, none.fx := fx, none.fishCol := fx >= 0
    if (bl < 0)
        return none
    bl := Round(bl) + 2, br := Round(br) - 2
    if p
        p.boxPrev := (bl + br) / 2, p.boxPrevT := now
    return {bar: true, bl: bl, br: br, fish: fx >= 0, fx: fx, cover: 1, n: br - bl + 1, fishCol: fx >= 0}
}

; The best pair of box sides along row y: the pair of thin black lines a
; bar-width apart whose heights overlap the most (the bar's sides are the
; tallest black lines on the reel; arrows and artwork are shorter). 0 if none.
BoxPick(b, y, w, minH, barW, near := -1, reach := 0, skip := 0) {
    cands := BoxCands(b, y, w, skip)
    if (cands.Length < 2 || cands.Length > 40)
        return 0
    want := barW ? barW * w : w * 0.30
    ; Noiseform's bar is 30% of the track: widths far from that are
    ; strongly discounted (dark streaks in its artwork can be tall)
    lo := barW ? (barW - 0.05) * w : w * 0.24, hi := barW ? (barW + 0.05) * w : w * 0.36
    spans := Map(), best := 0
    for i, a in cands
        for j, z in cands {
            if (j <= i || z - a < lo || z - a > hi || (near >= 0 && Abs((a + z) / 2 - near) > reach))
                continue
            if !spans.Has(i)
                spans[i] := BoxSpan(b, a, y)
            if !spans.Has(j)
                spans[j] := BoxSpan(b, z, y)
            top := Max(spans[i][1], spans[j][1]), bot := Min(spans[i][2], spans[j][2]), h := bot - top
            if (h < minH)
                continue
            sc := h * Max(0, 1 - 4 * Abs(z - a - want) / w)
            if (near >= 0)
                sc *= 1 - 0.5 * Abs((a + z) / 2 - near) / Max(1, reach)      ; nearer to where it was is better
            if (!best || sc > best.sc)
                best := {bl: a, br: z, top: top, bot: bot, h: h, sc: sc}
        }
    return best
}

; Searches the band for the tallest pair of box sides; returns the pair and
; the row through the middle of that box, or 0.
BoxFind(b, geo, barW := 0) {
    w := b.w, minH := Max(12, Round(geo.ih * 0.3)), best := 0, y := 1
    while (y < b.h - 1) {
        pk := BoxPick(b, y, w, minH, barW)
        if (pk && (!best || pk.sc > best.sc))
            best := pk
        y += 4
    }
    return best ? {pk: best, row: (best.top + best.bot) // 2} : 0
}

; Thin black runs along one band row: the centres of possible box sides.
BoxCands(b, y, w, skip := 0) {
    o := y * b.stride, maxW := Max(4, Round(w * 0.005)), out := [], rs := -1, x := 0, thr := 45
    while (x <= w) {
        dark := false
        if (x < w) {
            c := NumGet(b.bits, o + x * 4, "UInt")
            dark := ((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < thr
        }
        if dark {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            cx := (rs + x - 1) // 2, ok := (x - rs <= maxW && cx > w * 0.01 && cx < w * 0.99)
            if (ok && IsObject(skip))
                for sk in skip
                    if (cx >= sk[1] && cx <= sk[2])
                        ok := false
            if ok
                out.Push(cx)
            rs := -1
        }
        x++
    }
    return out
}


; Top and bottom rows of the black line through (x, y), bridging tiny gaps.
BoxSpan(b, x, y) {
    bits := b.bits, st := b.stride, o := x * 4, top := y, bot := y, t := y, thr := 45
    while (t > 0) {
        t--
        c := NumGet(bits, t * st + o, "UInt")
        if (((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < thr)
            top := t
        else if (top - t > 2)
            break
    }
    t := y
    while (t < b.h - 1) {
        t++
        c := NumGet(bits, t * st + o, "UInt")
        if (((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < thr)
            bot := t
        else if (t - bot > 2)
            break
    }
    return [top, bot]
}

; Dark runs of fish width along row y: [[centre, width], ...].
BoxRuns(b, y, w) {
    bits := b.bits, o := y * b.stride, runs := [], rs := -1, x := 0, thr := RowDark(b, y)
    lo := Max(3, Round(w * 0.004)), hi := Max(8, Round(w * 0.025))
    while (x <= w) {
        dark := false
        if (x < w) {
            c := NumGet(bits, o + x * 4, "UInt")
            dark := ((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < thr
        }
        if dark {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            n := x - rs
            if (n >= lo && n <= hi)
                runs.Push([rs + (n - 1) / 2, n])
            rs := -1
        }
        x++
    }
    return runs
}

;------------------------------------------------------------------------------
; Pinion's Aria, read by shape. Along the tube's middle row the bar's two end
; caps each show a thin near-white highlight, in both of the bar's colours
; (it darkens when the fish leaves it), and the fish is a wider white
; capsule. Measured on a real Pinion's Aria reel: caps 4 px, fish ~24 px,
; caps 30% of the track apart.
;------------------------------------------------------------------------------
CapWhite(c) => ((c >> 16) & 255) >= 216 && ((c >> 8) & 255) >= 216 && (c & 255) >= 216
; A cap's highlight: bright, whatever its tint (the bar is blue, dark blue or,
; with the fish outside it, red, and the highlights take on that tint).
CapBright(c) => Max((c >> 16) & 255, (c >> 8) & 255, c & 255) >= 200 && Min((c >> 16) & 255, (c >> 8) & 255, c & 255) >= 140

; How tall the bright line through (x, y) is: the fish's white core is tall,
; the 水 symbol printed on the bar is short.
BrightSpan(b, x, y) {
    top := y, bot := y, t := y, o := x * 4
    while (t > 0) {
        t--
        if CapBright(NumGet(b.bits, t * b.stride + o, "UInt"))
            top := t
        else if (top - t > 3)
            break
    }
    t := y
    while (t < b.h - 1) {
        t++
        if CapBright(NumGet(b.bits, t * b.stride + o, "UInt"))
            bot := t
        else if (t - bot > 3)
            break
    }
    return bot - top
}

; The band row where the caps' highlights show (the reel box may not sit
; centred on the tube): the row nearest the box's middle where a bar and a
; fish both read, else one where a bar reads.
CapRow(b, geo) {
    barOnly := 0
    Loop geo.ih + 1 {
        k := A_Index - 1, y := geo.r2 + ((k & 1) ? (k + 1) // 2 : -(k // 2))
        if (y < geo.m || y > geo.m + geo.ih)
            continue
        d := CapScan(b, geo, -1, {capRow: y, barW: 0})
        if (d.bar && d.fish)
            return y
        if (d.bar && !barOnly)
            barOnly := y
    }
    return barOnly ? barOnly : geo.r2
}

CapScan(b, geo, predFish := -1, p := 0) {
    global ShapeWhy
    w := b.w, bits := b.bits, barW := p ? p.barW : 0
    row := (p && p.capRow) ? p.capRow : geo.r2, o := row * b.stride, fishH := Max(12, Round(geo.ih * 0.3))
    ; the highlights sit on a narrow band of rows, which shifts a little with
    ; the bar's colour: read the chosen row and one a little above and below
    oU := Max(0, row - 3) * b.stride, oD := Min(b.h - 1, row + 3) * b.stride
    none := {bar: false, bl: -1, br: -1, fish: false, fx: -1, cover: 0, n: 0, fishCol: false}
    maxCap := Max(4, Round(w * 0.005)), fLo := Max(6, Round(w * 0.008)), fHi := Max(12, Round(w * 0.03))
    caps := [], fishes := [], rs := -1, x := 0
    while (x <= w) {
        on := false
        if (x < w) {
            on := CapBright(NumGet(bits, o + x * 4, "UInt")) || CapBright(NumGet(bits, oU + x * 4, "UInt")) || CapBright(NumGet(bits, oD + x * 4, "UInt"))
        }
        if on {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            n := x - rs, cx := rs + (n - 1) / 2
            if (n <= maxCap && cx > w * 0.01 && cx < w * 0.99)
                caps.Push(cx)
            else if (n >= fLo && n <= fHi && BrightSpan(b, Round(cx), row) >= fishH)
                fishes.Push(cx)
            rs := -1
        }
        x++
    }
    fx := -1, fb := 1e9
    for f in fishes {
        sc := predFish >= 0 ? Abs(f - predFish) : 0
        if (sc < fb)
            fb := sc, fx := f
    }
    none.fish := fx >= 0, none.fx := fx, none.fishCol := fx >= 0
    ; once the reel is running its width is known and held closely, and the
    ; pair nearest where the bar just was wins (strokes of the 水 symbol and
    ; sparkles are thin and bright too)
    ; Pinion's Aria's bar widens as notes are caught and narrows when they're
    ; missed, so the width isn't held to one value: the pair nearest the
    ; recent median width wins, within 15% of it
    if (p && p.HasOwnProp("capWs") && p.capWs.Length >= 5)
        barW := ZMedian(p.capWs) / w
    want := barW ? barW * w : w * 0.285
    lo := barW ? 0.85 * barW * w : w * 0.2, hi := barW ? 1.15 * barW * w : w * 0.6
    prev := (p && p.HasOwnProp("boxPrev") && p.boxPrev >= 0) ? p.boxPrev : -1
    bl := -1, br := -1, best := 1e9
    for i, a in caps
        for j, z in caps
            if (j > i && z - a >= lo && z - a <= hi) {
                sc := Abs(z - a - want) + (prev >= 0 ? 0.25 * Abs((a + z) / 2 - prev) : 0)
                if (sc < best)
                    best := sc, bl := a, br := z
            }
    ; one cap hidden (the fish passing over it): the other is a bar-width away
    if (bl < 0 && p && barW && p.HasOwnProp("boxPrev") && p.boxPrev >= 0) {
        bw := barW * w, bestD := w * 0.15
        for a in caps
            for opt in [[a, a + bw], [a - bw, a]]
                if (opt[1] >= -2 && opt[2] <= w + 1 && Abs((opt[1] + opt[2]) / 2 - p.boxPrev) < bestD)
                    bestD := Abs((opt[1] + opt[2]) / 2 - p.boxPrev), bl := opt[1], br := opt[2]
    }
    if (bl < 0) {
        ShapeWhy := Format("{} end-cap highlight(s) on the reel, but no two a bar-width apart", caps.Length)
        return none
    }
    if p {
        p.boxPrev := (bl + br) / 2
        if (best < 1e9) {                                    ; a real pair (not placed from one cap)
            if !p.HasOwnProp("capWs")
                p.capWs := []
            p.capWs.Push(Round(br - bl))
            if (p.capWs.Length > 15)
                p.capWs.RemoveAt(1)
        }
    }
    bl := Round(bl) + 3, br := Round(br) - 3
    return {bar: true, bl: bl, br: br, fish: fx >= 0, fx: fx, cover: 1, n: br - bl + 1, fishCol: fx >= 0}
}

;------------------------------------------------------------------------------
; Pinion's Aria notes: white 水 symbols fall straight down onto the reel
; (about 1.2 s from the top of the screen at 4K). Three thin rows high above
; the reel are watched; a note counts when it crosses one row and then the
; next one down on time, which a still white object never does. Its landing
; time and place are predicted, and the bar is aimed to cover it while
; keeping the fish inside when both fit.
;------------------------------------------------------------------------------
class NoteWatch {
    static grab := 0, geo := 0, tracks := [], notes := [], lastT := 0, f := 12, ax := 0, ay := 0, aw := 0, ah := 0, landY := 0, startT := 0
    ; The whole screen above the bar, shrunk so each cell averages f x f
    ; screen pixels (a note stays about five cells tall at any resolution):
    ; from near the top of the Roblox window down to just above the fish's
    ; ornament, across the reel's width.
    static Setup(geo, cr := 0) {
        top := cr ? cr.y + Round(cr.h * 0.05) : Max(0, geo.y - 26 * geo.ih)
        this.Area(geo, top, Max(4, Round(geo.ih / 5)))
        this.grab := ShrinkGrab(this.aw, this.ah, this.f)
    }
    static Area(geo, top, f) {
        this.geo := geo, this.f := f, this.ax := geo.x, this.aw := geo.w
        this.ay := top, this.ah := Max(f * 4, geo.y - 2 * geo.ih - top)
        this.landY := geo.y + geo.m + geo.ih // 2
        this.tracks := [], this.notes := [], this.lastT := 0, this.startT := 0
    }
    ; One look (live about 20 times a second; g: a shrunken image, for replay).
    static Update(now, g := 0) {
        if !IsObject(g) {
            if (!this.grab || now - this.lastT < 0.045)
                return
            this.grab.Grab(this.ax, this.ay)
            g := this.grab
        }
        dt := this.lastT ? now - this.lastT : 0.05
        this.lastT := now
        if !this.startT
            this.startT := now
        f := this.f, w := this.geo.w
        ; bright, colourless cells (notes are white); every other row is enough
        blobs := [], y := 0
        while (y < g.h) {
            o := y * g.stride, x := 0
            while (x < g.w) {
                c := NumGet(g.bits, o + x * 4, "UInt")
                r := (c >> 16) & 255, gg := (c >> 8) & 255, bb := c & 255, mn := Min(r, gg, bb)
                if (mn >= 120 && Max(r, gg, bb) - mn <= 70) {
                    hit := 0
                    for bl in blobs
                        if (Abs(bl.x / bl.n - x) <= 3 && Abs(bl.y / bl.n - y) <= 4) {
                            hit := bl
                            break
                        }
                    if hit
                        hit.x += x, hit.y += y, hit.n++
                    else
                        blobs.Push({x: x, y: y, n: 1})
                }
                x++
            }
            y += 2
        }
        ; follow each blob: a note falls straight down, speeding up
        v0 := 21.7 * this.geo.ih, reachX := Max(3 * f, w * 0.02)
        for bl in blobs {
            if (bl.n > 30)
                continue                                   ; far bigger than a note
            X := this.ax + (bl.x / bl.n + 0.5) * f, Y := this.ay + (bl.y / bl.n + 1) * f
            best := 0, bd := 1e9
            for tr in this.tracks {
                dy := Y - tr.y, lo := -2 * f, hi := 3 * v0 * (now - tr.t) + 3 * f
                if (tr.t < now && Abs(X - tr.x) <= reachX && dy >= lo && dy <= hi && Abs(X - tr.x) + Abs(dy) / 4 < bd)
                    bd := Abs(X - tr.x) + Abs(dy) / 4, best := tr
            }
            if best {
                vy := (Y - best.y) / Max(0.01, now - best.t)
                best.vy := best.n = 1 ? vy : 0.5 * best.vy + 0.5 * vy
                best.x := X, best.y := Y, best.t := now, best.n++
            } else
                this.tracks.Push({x: X, y: Y, x0: X, y0: Y, t: now, t0: now, vy: 0, n: 1})
        }
        keep := []
        for tr in this.tracks
            if (now - tr.t < 0.25)
                keep.Push(tr)
        this.tracks := keep
        ; notes: first seen near the top (where notes appear; the character
        ; below can move too), seen three times, falling straight down at note
        ; speed. They speed up as they fall (measured: about 19 reel-box
        ; heights per second, per second), so landing allows for that.
        this.notes := [], acc := 19 * this.geo.ih
        for tr in this.tracks
            ; (a reel opens with a splash washing down the screen: nothing first
            ; seen in its first 0.8 s counts)
            if (tr.n >= 3 && tr.t0 >= this.startT + 0.8 && tr.y0 < this.ay + 0.4 * this.ah && tr.vy > 0.25 * v0 && tr.vy < 3 * v0 && Abs(tr.x - tr.x0) < w * 0.04) {
                dist := Max(0, this.landY - tr.y)
                this.notes.Push({x: tr.x - this.ax, t: now + (Sqrt(tr.vy ** 2 + 2 * acc * dist) - tr.vy) / acc})
            }
    }
    ; Where the bar's centre should be now (band x), or -1 to follow the fish.
    ; Notes come first, but not at once: until the bar must leave, it keeps the
    ; fish and leans toward the note; it leaves just in time to reach it, and
    ; covers both when they fit.
    static Target(now, d) {
        if !d.bar
            return -1
        soon := 0
        for n in this.notes
            if (n.t > now - 0.05 && n.t - now < 1.6 && (!soon || n.t < soon.t))
                soon := n
        if !soon
            return -1
        bw := d.br - d.bl, r := bw / 2 - 0.12 * bw, c := (d.bl + d.br) / 2
        fx := d.fish ? d.fx : c
        goal := Abs(fx - soon.x) <= 2 * r ? Clamp(fx, soon.x - r, soon.x + r)   ; note and fish both in the bar
            : soon.x + (fx > soon.x ? r : -r)                                   ; the note, as near the fish as it can be
        travel := Abs(goal - c) / (0.45 * this.geo.w) + 0.15                    ; a cautious bar speed, plus reaction
        if (soon.t - now <= travel)
            return goal                                                         ; time to go
        return d.fish ? Clamp(soon.x, fx - r, fx + r) : -1                      ; not yet: keep the fish, lean toward the note
    }
}

; White runs of note width along a one-row grab: their centres.
NoteRuns(g, w) {
    runs := [], rs := -1, x := 0, lo := Max(6, Round(w * 0.01)), hi := Round(w * 0.06)
    while (x <= w) {
        on := x < w && CapWhite(NumGet(g.bits, x * 4, "UInt"))
        if (on && rs < 0)
            rs := x
        else if (!on && rs >= 0) {
            if (x - rs >= lo && x - rs <= hi)
                runs.Push(rs + (x - rs - 1) / 2)
            rs := -1
        }
        x++
    }
    return runs
}

;------------------------------------------------------------------------------
; Noiseform zones. Before three zones appear on the track, a big see-through
; copy of the correct one flashes three times in the middle of the screen: a
; dark triangle, a green circle or a light-grey square. The zones on the track
; carry the same colours around their white icons. The flash is read on two
; rings of points around the middle of the screen (the character stands in
; the middle and its glow keeps changing, so only the rings are read, each
; compared with the last second); the bar is then taken to the zone of that
; colour until the beam strikes. Measured on a real Noiseform recording:
; flashes 0.3 s apart, zones ~0.5 s after the last one, the beam 0.5-1 s later.
;------------------------------------------------------------------------------
class ZoneWatch {
    static grab := 0, pts := [], hist := [], spikes := [], want := "", wantAt := 0, zonesAt := 0, lastT := 0, gx := 0, gy := 0
    static votes := Map(), lockX := -1
    static Setup(cr) {
        h := cr.h, side := 2 * Round(0.125 * h) + 8
        this.gx := cr.x + cr.w // 2 - side // 2, this.gy := cr.y + Round(0.5046 * h) - side // 2
        this.grab := BandGrab(side, side)
        this.Points(side // 2, side // 2, h)
    }
    static Points(cx, cy, h) {
        this.pts := [], this.hist := [], this.spikes := [], this.want := "", this.wantAt := 0, this.zonesAt := 0, this.lastT := 0
        this.votes := Map(), this.lockX := -1
        for rf in [0.125, 0.10]
            Loop 48 {
                a := 2 * 3.14159265 * (A_Index - 1) / 48
                this.pts.Push([cx + Round(rf * h * Cos(a)), cy + Round(rf * h * Sin(a))])
            }
    }
    ; One look at the middle of the screen (g: a grab to read instead, for replay).
    static Update(now, g := 0) {
        global CurRod
        if (!IsObject(g) && now - this.lastT < 0.028)
            return
        this.lastT := now
        if !IsObject(g) {
            this.grab.Grab(this.gx, this.gy)
            g := this.grab
        }
        nG := 0, nK := 0, nW := 0
        for pt in this.pts {
            c := NumGet(g.bits, pt[2] * g.stride + pt[1] * 4, "UInt")
            r := (c >> 16) & 255, gg := (c >> 8) & 255, bb := c & 255
            mx := Max(r, gg, bb), mn := Min(r, gg, bb)
            nG += (gg - Max(r, bb) > 50 && gg > 150)
            nK += (((2 * r + 5 * gg + bb) >> 3) < 40)
            nW += (mn >= 140 && mx - mn < 45)
        }
        cnt := [nG, nK, nW]
        if (this.hist.Length >= 11) {
            for k, name in ["green", "dark", "gray"] {
                v := []
                Loop this.hist.Length - 3
                    v.Push(this.hist[A_Index][k])
                if (cnt[k] - ZMedian(v) >= 25) {
                    last := 0
                    for s in this.spikes
                        if (s.k = name)
                            last := s
                    if (last && now - last.t <= 0.15)
                        last.t := now                     ; the same flash, still showing
                    else
                        this.spikes.Push({k: name, t: now})
                }
            }
        }
        this.hist.Push(cnt)
        if (this.hist.Length > 33)
            this.hist.RemoveAt(1)
        keep := []
        for s in this.spikes
            if (now - s.t < 1.2)
                keep.Push(s)
        this.spikes := keep
        ; two flashes of one colour: that colour's zone is the one to take
        ; at night most of the ring is dark already: a dark flash can't be told
        ; apart (and fading flashes look like one), so only green and grey count
        night := false
        if (this.hist.Length >= 11) {
            v := []
            for h in this.hist
                v.Push(h[2])
            night := ZMedian(v) > 0.6 * this.pts.Length
        }
        for name in ["green", "dark", "gray"] {
            if (name = "dark" && night)
                continue
            n := 0
            for s in this.spikes
                n += (s.k = name)
            ; one decision holds until its zones are gone (or 3.5 s pass)
            if (n >= 2 && this.want = "" || n >= 2 && now - this.wantAt > 3.5)
                this.want := name, this.wantAt := now, this.zonesAt := 0, this.votes := Map(), this.lockX := -1
                    , LogVision("Noiseform zone: the " (name = "dark" ? "black triangle" : name = "green" ? "green circle" : "grey square") " flashed")
        }
    }
    ; Where the bar's centre should go now (band x), or -1 to follow the fish.
    static Target(now, b, geo, p := 0) {
        if (this.want = "" || now - this.wantAt > 3.5)
            return -1
        if (p && (!p.zoneRow || (this.zonesAt && now - this.zonesAt > 0.12)))
            if (r := ZoneRow(b, geo))
                p.zoneRow := r
        zs := FindZones(b, geo, p)
        if zs.Length
            this.zonesAt := now
        else if (this.zonesAt && now - this.zonesAt > 0.25) {
            this.want := "", this.lockX := -1             ; the beam has struck
            if p
                p.zoneRow := 0
            LogVision("Noiseform zone: zones gone, back to the fish")
            return -1
        }
        if (this.lockX >= 0)
            return this.lockX                             ; zones don't move once they're up
        ; a zone can read as the wrong colour for a frame (the fish or the dark
        ; bar passing over it), so its place is confirmed over several looks
        step := Max(8, b.w * 0.03)
        for z in zs
            if (z.k = this.want) {
                k := Round(z.x / step)
                v := this.votes.Has(k) ? this.votes[k] : {n: 0, sum: 0}
                v.n++, v.sum += z.x, this.votes[k] := v
            }
        ; neighbouring bins count together
        best := 0, bestK := 0, bestN := 0, secondN := 0
        for k, v in this.votes {
            n := v.n, sum := v.sum
            for kk in [k - 1, k + 1]
                if this.votes.Has(kk)
                    n += this.votes[kk].n, sum += this.votes[kk].sum
            if (n > bestN)
                bestK := k, bestN := n, best := {n: n, sum: sum}
        }
        for k, v in this.votes
            if (Abs(k - bestK) > 2)
                secondN := Max(secondN, v.n)
        if (best && bestN >= 3 && bestN >= 2 * secondN) {
            this.lockX := best.sum / best.n
            LogVision(Format("Noiseform zone: taking the bar to the {} zone at {:.0f}% of the reel", this.want = "dark" ? "black" : this.want = "green" ? "green" : "grey", 100 * this.lockX / b.w))
        }
        return this.lockX
    }
}

ZMedian(v) {
    if !v.Length
        return 0
    s := ""
    for x in v
        s .= Format("{:06}", x) "`n"
    a := StrSplit(Sort(RTrim(s, "`n")), "`n")
    return Integer(a[(a.Length + 1) // 2])
}

; The zones on the reel: each has a white icon in its middle and its colour
; (dark, green or light grey) around it. [{x, k}] in band x.
FindZones(b, geo, p := 0) {
    w := b.w, zs := [], hiW := Max(8, Round(w * 0.03))
    ; the row the zone icons sit on: found by searching once per zone event
    ; (ZoneRow), else the reel area's middle
    mid := (p && p.HasOwnProp("zoneRow") && p.zoneRow) ? p.zoneRow : geo.m + geo.ih // 2
    hh := geo.ih
    o1 := Clamp(mid - Round(hh * 0.05), 0, b.h - 1) * b.stride, o2 := Clamp(mid + Round(hh * 0.05), 0, b.h - 1) * b.stride
    rs := -1, x := 0
    while (x <= w) {
        white := false
        if (x < w) {
            c := NumGet(b.bits, o1 + x * 4, "UInt")
            white := ((c >> 16) & 255) > 200 && ((c >> 8) & 255) > 200 && (c & 255) > 200
            if !white {
                c := NumGet(b.bits, o2 + x * 4, "UInt")
                white := ((c >> 16) & 255) > 200 && ((c >> 8) & 255) > 200 && (c & 255) > 200
            }
        }
        if white {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            n := x - rs
            if (n >= 4 && n <= hiW) {
                cx := rs + (n - 1) // 2, k := ZoneColour(b, geo, cx, mid, hh)
                if (k != "")
                    zs.Push({x: cx, k: k})
            }
            rs := -1
        }
        x++
    }
    ; an icon can read as two pieces (the triangle and its "!"): pieces closer
    ; than any two zones can be are one zone
    out := []
    for z in zs
        if (out.Length && z.x - out[out.Length].x < w * 0.04 && z.k = out[out.Length].k)
            out[out.Length].x := (out[out.Length].x + z.x) / 2
        else
            out.Push(z)
    return out
}

ZoneColour(b, geo, cx, mid := -1, hh := 0) {
    w := b.w, votes := Map("dark", 0, "green", 0, "gray", 0)
    mid := mid >= 0 ? mid : geo.m + geo.ih // 2, hh := hh ? hh : geo.ih
    for f in [-0.040, -0.035, -0.030, 0.030, 0.035, 0.040] {
        x := cx + Round(f * w)
        if (x < 0 || x >= w)
            continue
        for fy in [-0.3, 0, 0.3] {
            c := NumGet(b.bits, Clamp(mid + Round(hh * fy), 0, b.h - 1) * b.stride + x * 4, "UInt")
            r := (c >> 16) & 255, g := (c >> 8) & 255, bb := c & 255, lum := (2 * r + 5 * g + bb) >> 3
            if (lum < 45)
                votes["dark"]++
            else if (g - Max(r, bb) > 40)
                votes["green"]++
            else if (Max(r, g, bb) - Min(r, g, bb) < 55 && lum >= 70 && lum <= 230)   ; grey (tinted at night)
                votes["gray"]++
        }
    }
    best := "", bn := 4
    for k, n in votes
        if (n > bn)
            best := k, bn := n
    return best
}

; How dark "dark" is along a row: 60% of the row's typical brightness, at
; most 45. In daylight that's 45; at night, when the whole scene is dark,
; only lines darker than their surroundings count. Sampled every 8th pixel.
RowDark(b, y) {
    o := y * b.stride, v := "", x := 0
    while (x < b.w) {
        c := NumGet(b.bits, o + x * 4, "UInt")
        v .= Format("{:03}", (((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) "`n"
        x += 8
    }
    a := StrSplit(Sort(RTrim(v, "`n")), "`n")
    return Clamp(Round(0.6 * Integer(a[(a.Length + 1) // 2])), 12, 45)
}

; The row the zone icons sit on: the row near the reel with the most
; icon-sized white spots (the icons are the brightest things on the reel).
; Searched once when a warning is being acted on; 0 if no row has two.
ZoneRow(b, geo) {
    w := b.w, hiW := Max(8, Round(w * 0.03)), best := 0, bestN := 1
    y := Max(0, geo.m - Round(geo.ih * 0.3))
    while (y <= Min(b.h - 1, geo.m + geo.ih + Round(geo.ih * 0.3))) {
        o := y * b.stride, n := 0, rs := -1, x := 0
        while (x <= w) {
            white := false
            if (x < w) {
                c := NumGet(b.bits, o + x * 4, "UInt")
                white := ((c >> 16) & 255) > 200 && ((c >> 8) & 255) > 200 && (c & 255) > 200
            }
            if (white && rs < 0)
                rs := x
            else if (!white && rs >= 0) {
                n += (x - rs >= 4 && x - rs <= hiW)
                rs := -1
            }
            x++
        }
        if (n > bestN)
            bestN := n, best := y
        y += 2
    }
    return best
}

;------------------------------------------------------------------------------
; Narrow runs along row y whose pixels pass test: their centres.
LiteColourRuns(b, y, lo, hi, test) {
    o := y * b.stride, out := [], st := -1, x := 0
    while (x <= b.w) {
        on := x < b.w && test(NumGet(b.bits, o + x * 4, "UInt"))
        if (on && st < 0)
            st := x
        else if (!on && st >= 0) {
            if (x - st >= lo && x - st <= hi)
                out.Push(st + (x - st - 1) / 2)
            st := -1
        }
        x++
    }
    return out
}

; Pinion's Aria without a skin. A pale tube; the bar is a rounded box a little
; taller than the tube (pastel with the fish in it, dark red without, with a
; light border either way), and the fish is a capsule taller still whose top
; is a strong cyan. So on a row just above the tube and one just below, only
; the bar and the fish show against the background: the bar as a bright run
; a bar-width long, the fish as a narrow cyan run. Measured on a real reel.
;------------------------------------------------------------------------------
; Brightness of a pixel (0-255).
Lum(c) => (((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3

; The tube's top and bottom rows in the band: rows where one bright run
; crosses most of the band, around the reel area's middle. [top, bottom] or 0.
LiteRows(b, geo) {
    ; a tube row is largely pale and washed-out (the tube, and the bar in
    ; most of its looks) or the bar's bright red; the scene behind is more
    ; saturated. No single run is required: the bar can cut the tube in two.
    long := [], y := 0
    while (y < b.h) {
        o := y * b.stride, n := 0, x := 0
        while (x < b.w) {
            c := NumGet(b.bits, o + x * 4, "UInt")
            r := (c >> 16) & 255, g := (c >> 8) & 255, bb := c & 255
            n += (Lum(c) >= 130 && Max(r, g, bb) - Min(r, g, bb) <= 60) || (r >= 150 && r - g >= 80)
            x += 2
        }
        if (2 * n >= b.w * 0.45)
            long.Push(y)
        y += 1
    }
    if (long.Length < 3)
        return 0
    mid := geo.m + geo.ih // 2, top := long[1], bot := long[1], bestT := 0, bestB := 0, bestD := 1e9
    for i, y in long {
        if (i > 1 && y - long[i - 1] > 2)
            top := y
        bot := y
        d := (mid >= top && mid <= bot) ? 0 : Min(Abs(mid - top), Abs(mid - bot))
        if (d < bestD || (d = bestD && bot - top > bestB - bestT))
            bestD := d, bestT := top, bestB := bot
    }
    return bestB - bestT >= 4 ? [bestT, bestB] : 0
}

; Runs along row y, a bar-width long, of pixels clearly unlike the row's
; background (the bar box is pastel, dark red-grey or bright red, so it's told
; from the background by colour, not brightness): [[left, right], ...].
LiteBarRuns(b, y, lo, hi) {
    o := y * b.stride, rs := [], gs := [], bs := [], x := 0
    while (x < b.w) {
        c := NumGet(b.bits, o + x * 4, "UInt")
        rs.Push(Format("{:03}", (c >> 16) & 255)), gs.Push(Format("{:03}", (c >> 8) & 255)), bs.Push(Format("{:03}", c & 255))
        x += 8
    }
    med(a) {
        t := ""
        for v in a
            t .= v "`n"
        q := StrSplit(Sort(RTrim(t, "`n")), "`n")
        return Integer(q[(q.Length + 1) // 2])
    }
    br := med(rs), bg := med(gs), bb := med(bs)
    out := [], st := -1, gap := 0, last := 0, x := 0
    while (x <= b.w) {
        on := false
        if (x < b.w) {
            c := NumGet(b.bits, o + x * 4, "UInt")
            on := Max(Abs(((c >> 16) & 255) - br), Abs(((c >> 8) & 255) - bg), Abs((c & 255) - bb)) > 50
        }
        if on {
            if (st < 0)
                st := x
            gap := 0, last := x
        } else if (st >= 0 && ++gap > 3) {
            if (last - st + 1 >= lo && last - st + 1 <= hi)
                out.Push([st, last])
            st := -1
        }
        x++
    }
    return out
}

LiteScan(b, geo, predFish := -1, p := 0) {
    global ShapeWhy
    w := b.w, none := {bar: false, bl: -1, br: -1, fish: false, fx: -1, cover: 0, n: 0, fishCol: false}
    if (p && p.HasOwnProp("trkT") && p.trkT)
        rows := [p.trkT, p.trkB]
    else if (rows := LiteRows(b, geo)) {
        if p
            p.trkT := rows[1], p.trkB := rows[2]
    } else {
        ShapeWhy := "no pale tube across the reel"
        return none
    }
    th := rows[2] - rows[1]
    yU := Max(0, rows[1] - Max(2, Round(th * 0.1))), yD := Min(b.h - 1, rows[2] + Max(2, Round(th * 0.12)))
    ; the bar widens as notes are caught and narrows when they're missed:
    ; the run nearest the recent median width wins, within 15% of it
    barW := p ? p.barW : 0
    if (p && p.HasOwnProp("liteWs") && p.liteWs.Length >= 5)
        barW := ZMedian(p.liteWs) / w
    lo := barW ? 0.85 * barW * w : w * 0.2, hi := barW ? 1.15 * barW * w : w * 0.6
    ; the fish: a capsule whose top is strongly cyan and reaches well above the
    ; bar box: a narrow cyan run just above the tube and another higher up,
    ; above the box, at the same place (other cyan things don't reach there)
    fLo := Max(3, Round(w * 0.004)), fHi := Max(8, Round(w * 0.02)), tol := Max(3, Round(w * 0.006))
    yF := Max(0, rows[1] - Round(th * 0.33))
    cyan := (c) => (c & 255) >= 200 && (c & 255) - ((c >> 16) & 255) >= 120
    lowC := LiteColourRuns(b, yU, fLo, fHi, cyan), highC := LiteColourRuns(b, yF, fLo, fHi, cyan)
    fx := -1, fb := 1e9
    for u in lowC
        for v in highC
            if (Abs(u - v) <= tol) {
                cen := (u + v) / 2, sc := predFish >= 0 ? Abs(cen - predFish) : 0
                if (sc < fb)
                    fb := sc, fx := cen
            }
    none.fish := fx >= 0, none.fx := fx, none.fishCol := fx >= 0
    ; the bar: the same bright run just above and just below the tube
    up := LiteBarRuns(b, yU, lo, hi), dn := LiteBarRuns(b, yD, lo, hi)
    prev := (p && p.HasOwnProp("boxPrev") && p.boxPrev >= 0) ? p.boxPrev : -1
    bl := -1, br := -1, best := 1e9
    for u in up
        for v in dn {
            ov := Min(u[2], v[2]) - Max(u[1], v[1])
            if (ov < 0.7 * Min(u[2] - u[1], v[2] - v[1]))
                continue
            l := (u[1] + v[1]) / 2, r := (u[2] + v[2]) / 2
            sc := (barW ? Abs(r - l - barW * w) : 0) + (prev >= 0 ? 0.25 * Abs((l + r) / 2 - prev) : 0)
            if (!barW && (r - l < w * 0.2 || r - l > w * 0.6))
                continue
            if (sc < best)
                best := sc, bl := l, br := r
        }
    if (bl < 0) {
        ShapeWhy := Format("no bar-width bright box above and below the tube ({} / {} run(s))", up.Length, dn.Length)
        if p {
            p.liteMiss := (p.HasOwnProp("liteMiss") ? p.liteMiss : 0) + 1
            if (p.liteMiss >= 8)
                p.trkT := 0, p.liteMiss := 0            ; look for the tube again
        }
        return none
    }
    if p {
        p.boxPrev := (bl + br) / 2, p.liteMiss := 0
        if !p.HasOwnProp("liteWs")
            p.liteWs := []
        p.liteWs.Push(Round(br - bl))
        if (p.liteWs.Length > 15)
            p.liteWs.RemoveAt(1)
    }
    bl := Round(bl) + 4, br := Round(br) - 4
    return {bar: true, bl: bl, br: br, fish: fx >= 0, fx: fx, cover: 1, n: br - bl + 1, fishCol: fx >= 0}
}

;------------------------------------------------------------------------------
; Requiem. A dark track; the bar is a teal box (darker at its top, brighter
; below) with black arrows in it; the fish is a dark capsule, nearly the
; track's colour, that sticks out above and below the box. So the bar is the
; long teal run across the reel (bridging the arrows and the fish), and the
; fish a narrow dark run just above the box and just below it, where the
; scene behind is lighter. Measured on a real Requiem reel.
;------------------------------------------------------------------------------
TealPx(c) => Lum(c) >= 45 && ((c >> 8) & 255) - ((c >> 16) & 255) >= 30

TealScan(b, geo, predFish := -1, p := 0, test := TealPx, edgeLum := 85, what := "teal") {
    global ShapeWhy
    w := b.w, none := {bar: false, bl: -1, br: -1, fish: false, fx: -1, cover: 0, n: 0, fishCol: false}
    ; the bar along the reel's middle rows (each column's middle colour)
    bridge := Max(6, Round(w * 0.035)), best := 0, st := -1, gap := 0, last := 0, x := 0
    while (x <= w) {
        on := x < w && test(NumGet(b.cols, x * 4, "UInt"))
        if on {
            if (st < 0)
                st := x
            gap := 0, last := x
        } else if (st >= 0 && ++gap > bridge) {
            if (!best || last - st > best[2] - best[1])
                best := [st, last]
            st := -1
        }
        x++
    }
    barW := p ? p.barW : 0
    if (!best || best[2] - best[1] < w * 0.12 || best[2] - best[1] > w * 0.9) {
        ShapeWhy := "no " what " bar across the reel"
        none.fish := false
        return none
    }
    bl := best[1], br := best[2]
    ; the box's top and bottom: going up and down its own columns (a third
    ; and two thirds across, clear of the arrows) until the lighter scene
    ; behind begins (the box's top is too dark to follow by its teal)
    top := b.h, bot := 0
    for f in [0.33, 0.67] {
        cx := Round(bl + (br - bl) * f), o := cx * 4, t := geo.r2, u := geo.r2
        while (t > 0 && Lum(NumGet(b.bits, (t - 1) * b.stride + o, "UInt")) < edgeLum)
            t--
        while (u < b.h - 1 && Lum(NumGet(b.bits, (u + 1) * b.stride + o, "UInt")) < edgeLum)
            u++
        top := Min(top, t), bot := Max(bot, u)
    }
    if (bot - top < 6)
        top := geo.m, bot := geo.m + geo.ih
    ; the fish: a narrow run just above the box, clearly darker than the scene
    ; there; confirmed (when it can be) by a darker run just below the box,
    ; where the capsule is paler
    off := Max(2, Round((bot - top) * 0.06))
    up := TealDarkRuns(b, Clamp(top - off, 0, b.h - 1), w, 40), dn := TealDarkRuns(b, Clamp(bot + off, 0, b.h - 1), w, 12)
    fx := -1, fb := 1e9, tol := Max(3, Round(w * 0.006))
    for u in up {
        conf := false
        for v in dn
            if (Abs(u - v) <= tol)
                conf := true
        sc := (conf ? 0 : w * 0.1) + (predFish >= 0 ? Abs(u - predFish) : 0)
        if (sc < fb)
            fb := sc, fx := u
    }
    if p
        p.boxPrev := (bl + br) / 2
    return {bar: true, bl: bl, br: br, fish: fx >= 0, fx: fx, cover: 1, n: br - bl + 1, fishCol: fx >= 0}
}

; Narrow runs along row y darker than the row's typical brightness by delta:
; their centres.
TealDarkRuns(b, y, w, delta) {
    o := y * b.stride, v := "", x := 0
    while (x < w) {
        v .= Format("{:03}", Lum(NumGet(b.bits, o + x * 4, "UInt"))) "`n"
        x += 8
    }
    a := StrSplit(Sort(RTrim(v, "`n")), "`n"), thr := Integer(a[(a.Length + 1) // 2]) - delta
    out := [], st := -1, x := 0, lo := Max(3, Round(w * 0.004)), hi := Max(8, Round(w * 0.025))
    while (x <= w) {
        on := x < w && Lum(NumGet(b.bits, o + x * 4, "UInt")) < thr
        if (on && st < 0)
            st := x
        else if (!on && st >= 0) {
            if (x - st >= lo && x - st <= hi)
                out.Push(st + (x - st - 1) / 2)
            st := -1
        }
        x++
    }
    return out
}

;------------------------------------------------------------------------------
; Verdant Oath. The bar is two brown wooden blocks with the green zone between
; them (bright at its edges, nearly black in the middle, growing as the fish
; is kept in it); the fish is a grey capsule that sticks out above and below
; the blocks. So the blocks are found as two brown runs of about the same
; width, the bar spans their outer edges and the zone is the gap between them;
; the fish is a narrow grey run just above the blocks and just below them.
; Measured on a real Verdant Oath reel.
;------------------------------------------------------------------------------
WoodPx(c) {
    r := (c >> 16) & 255, g := (c >> 8) & 255, bb := c & 255
    return (r >= 78 && r - bb >= 35 && g - bb >= 12 && r >= g + 10)   ; brown
        || (r >= 90 && r - g >= 50 && r - bb >= 50)                     ; dark red (the red flash)
}
GreyPx(c) {
    r := (c >> 16) & 255, g := (c >> 8) & 255, bb := c & 255, l := Lum(c)
    return Max(r, g, bb) - Min(r, g, bb) <= 30 && l >= 45 && l <= 125
}

WoodScan(b, geo, predFish := -1, p := 0) {
    global ShapeWhy
    w := b.w, none := {bar: false, bl: -1, br: -1, fish: false, fx: -1, cover: 0, n: 0, fishCol: false}
    ; brown runs along the reel's middle rows (each column's middle colour)
    runs := [], st := -1, gap := 0, last := 0, x := 0
    while (x <= w) {
        on := x < w && WoodPx(NumGet(b.cols, x * 4, "UInt"))
        if on {
            if (st < 0)
                st := x
            gap := 0, last := x
        } else if (st >= 0 && ++gap > 3) {
            if (last - st >= w * 0.03 && last - st <= w * 0.25)
                runs.Push([st, last])
            st := -1
        }
        x++
    }
    ; the two blocks: about the same width, the zone between them. At either
    ; end of the reel the outer block can run past the edge of what's watched:
    ; a block touching the edge is taken as the other's width.
    prev := (p && p.HasOwnProp("boxPrev") && p.boxPrev >= 0) ? p.boxPrev : -1
    best := 0, bs := 1e9
    for i, a in runs
        for j, z in runs {
            if (j <= i)
                continue
            wa := a[2] - a[1], wz := z[2] - z[1], gz := z[1] - a[2]
            cutA := a[1] <= 2, cutZ := z[2] >= w - 3
            if (gz < w * 0.01 || gz > w * 0.7)
                continue
            if (!cutA && !cutZ && Min(wa, wz) < 0.6 * Max(wa, wz))
                continue
            if (cutA && wa > wz * 1.2 || cutZ && wz > wa * 1.2)
                continue
            sc := ((cutA || cutZ) ? 0 : Abs(wa - wz)) + (prev >= 0 ? 0.25 * Abs((a[1] + z[2]) / 2 - prev) : 0)
            if (sc < bs)
                bs := sc, best := [a, z, cutA, cutZ]
        }
    if !best {
        ShapeWhy := Format("{} brown block(s) on the reel, but no matching pair", runs.Length)
        return none
    }
    a := best[1], z := best[2], bl := a[1], br := z[2], zc := (a[2] + z[1]) / 2
    if best[3]
        bl := a[2] - (z[2] - z[1])                ; left block partly out of view
    if best[4]
        br := z[1] + (a[2] - a[1])                ; right block partly out of view
    ; the blocks' top and bottom, down the middle of the left block
    cx := (a[1] + a[2]) // 2, o := cx * 4, top := geo.r2, bot := geo.r2
    while (top > 0 && WoodPx(NumGet(b.bits, (top - 1) * b.stride + o, "UInt")))
        top--
    while (bot < b.h - 1 && WoodPx(NumGet(b.bits, (bot + 1) * b.stride + o, "UInt")))
        bot++
    if (bot - top < 6)
        top := geo.m, bot := geo.m + geo.ih
    ; the fish: narrow and grey just above the blocks and just below them
    off := Max(2, Round((bot - top) * 0.15))
    up := WoodGreyRuns(b, Clamp(top - off, 0, b.h - 1), w), dn := WoodGreyRuns(b, Clamp(bot + off, 0, b.h - 1), w)
    fx := -1, fb := 1e9, tol := Max(3, Round(w * 0.006))
    for u in up
        for v in dn
            if (Abs(u - v) <= tol) {
                cen := (u + v) / 2, sc := predFish >= 0 ? Abs(cen - predFish) : 0
                if (sc < fb)
                    fb := sc, fx := cen
            }
    ; or, failing that, a narrow grey run along the reel's middle rows (it shows
    ; against the dark track, the brown blocks and the zone)
    if (fx < 0) {
        st := -1, x := 0, lo := Max(3, Round(w * 0.003)), hi := Max(8, Round(w * 0.02))
        while (x <= w) {
            on := x < w && GreyPx(NumGet(b.cols, x * 4, "UInt"))
            if (on && st < 0)
                st := x
            else if (!on && st >= 0) {
                if (x - st >= lo && x - st <= hi) {
                    cen := st + (x - st - 1) / 2, sc := predFish >= 0 ? Abs(cen - predFish) : 0
                    if (sc < fb)
                        fb := sc, fx := cen
                }
                st := -1
            }
            x++
        }
    }
    if p
        p.boxPrev := (bl + br) / 2
    return {bar: true, bl: bl, br: br, zc: zc, fish: fx >= 0, fx: fx, cover: 1, n: br - bl + 1, fishCol: fx >= 0}
}

WoodGreyRuns(b, y, w) {
    o := y * b.stride, out := [], st := -1, x := 0, lo := Max(3, Round(w * 0.004)), hi := Max(8, Round(w * 0.02))
    while (x <= w) {
        on := x < w && GreyPx(NumGet(b.bits, o + x * 4, "UInt"))
        if (on && st < 0)
            st := x
        else if (!on && st >= 0) {
            if (x - st >= lo && x - st <= hi)
                out.Push(st + (x - st - 1) / 2)
            st := -1
        }
        x++
    }
    return out
}

;------------------------------------------------------------------------------
; Apollo's Sunshot. Built like Requiem's reel: a dark track; the bar a brown
; box (with a yellow arrow) a little taller than the track; the fish a dark
; capsule sticking out above and below the box. The charge meter riding above
; the bar isn't read. Measured on a real Apollo's Sunshot reel.
;------------------------------------------------------------------------------
SunPx(c) {
    r := (c >> 16) & 255, g := (c >> 8) & 255, bb := c & 255
    return r >= 60 && r - bb >= 25 && r - g >= 15
}
SunScan(b, geo, predFish := -1, p := 0) => TealScan(b, geo, predFish, p, SunPx, 76, "brown")


;==============================================================================
; Extras: logo graphics, auto totems, Sovereign recharge, Discord alerts and
; auto-reconnect.
;==============================================================================

;------------------------------------------------------------------------------
; GDI+ for the logo, icons and PNG snapshots
;------------------------------------------------------------------------------
class Gdip {
    static token := 0, streams := []
    static Start() {
        if this.token
            return true
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut("UInt", 1, si, 0)
        if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
            return false
        this.token := tok
        return true
    }
    static Stop() {
        for st in this.streams
            try ObjRelease(st)
        this.streams := []
        if this.token
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this.token), this.token := 0
    }
}

; Decodes base64 PNG data into a GDI+ bitmap. Its stream stays alive with it.
GpFromBase64(b64) {
    if !Gdip.Start()
        return 0
    if !DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n := 0, "Ptr", 0, "Ptr", 0)
        return 0
    buf := Buffer(n)
    DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
    st := DllCall("shlwapi\SHCreateMemStream", "Ptr", buf, "UInt", n, "Ptr")
    if !st
        return 0
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", st, "Ptr*", &bmp)
    Gdip.streams.Push(st)
    return bmp
}

; A scaled copy of a GDI+ bitmap as an HBITMAP over a solid background.
GpScaled(src, w, h, bgRGB := 0) {
    if !src
        return 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0xFF000000 | bgRGB)
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", src, "UInt*", &sw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &sh := 0)
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", g, "Ptr", src, "Int", 0, "Int", 0, "Int", w, "Int", h
        , "Int", 0, "Int", 0, "Int", sw, "Int", sh, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", dst, "Ptr*", &hbm := 0, "UInt", 0xFF000000 | bgRGB)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
    return hbm
}

; An icon of the app tile at `px` pixels, for the tray and title bar.
GpIcon(src, px) {
    if !src
        return 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", px, "Int", px, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0)
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", src, "UInt*", &sw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &sh := 0)
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", g, "Ptr", src, "Int", 0, "Int", 0, "Int", px, "Int", px
        , "Int", 0, "Int", 0, "Int", sw, "Int", sh, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipCreateHICONFromBitmap", "Ptr", dst, "Ptr*", &hicon := 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
    return hicon
}

; Saves an HBITMAP as a PNG file. True on success.
SavePng(hbm, path) {
    if (!hbm || !Gdip.Start())
        return false
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &bmp)
    if !bmp
        return false
    clsid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
    r := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bmp, "WStr", path, "Ptr", clsid, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
    return r = 0
}

LogoImage(which) {
    static cache := Map()
    if !cache.Has(which)
        cache[which] := GpFromBase64(LogoData(which))
    return cache[which]
}

; The tray and title-bar icon: the fish on a black tile.
ApplyAppIcon(hwnd := 0) {
    static small := 0, big := 0
    if !small
        small := GpIcon(LogoImage("icon"), 16), big := GpIcon(LogoImage("icon"), 32)
    if !small
        return
    try TraySetIcon("HICON:*" big)
    if hwnd {
        SendMessage(0x80, 0, small, , "ahk_id " hwnd)
        SendMessage(0x80, 1, big, , "ahk_id " hwnd)
    }
}

;------------------------------------------------------------------------------
; Auto totems. Each entry: name, hotbar key, how often, whether it needs night.
; Stored in [Totems] as  1=Aurora|5|20|1|1  (name|key|minutes|on|night).
;------------------------------------------------------------------------------

LoadTotems() {
    Totems.Length := 0
    try section := IniRead(IniPath, "Totems")
    catch
        return
    Loop Parse, section, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^\d+=(.*)$", &m)
            continue
        f := StrSplit(m[1], "|")
        if (f.Length < 5 || Trim(f[1]) = "" || Totems.Length >= TOTEM_MAX)
            continue
        Totems.Push({name: f[1], slot: f[2], every: Clamp(Round(f[3] + 0), 1, 240), on: f[4] ? 1 : 0, night: f[5] ? 1 : 0, next: 0})
    }
}

SaveTotems() {
    if NoSave
        return
    try IniDelete(IniPath, "Totems")
    for i, t in Totems
        try IniWrite(Format("{}|{}|{}|{}|{}", RegExReplace(t.name, "[|=\r\n]", " "), t.slot, t.every, t.on, t.night), IniPath, "Totems", i)
}

AddTotem(name, *) {
    if (Totems.Length >= TOTEM_MAX)
        return SetDetail("Up to " TOTEM_MAX " totems can be scheduled.")
    night := 0
    for p in TotemPresets
        if (p[1] = name)
            night := p[2]
    Totems.Push({name: name, slot: "", every: name = "Sundial" ? 10 : 15, on: 1, night: night, next: 0})
    SaveTotems()
    try TotemsChanged()
    SetDetail("Added the " name " Totem. Set its hotbar key so the macro can use it.")
}

RemoveTotem(i, *) {
    if (i < 1 || i > Totems.Length)
        return
    name := Totems[i].name
    Totems.RemoveAt(i)
    SaveTotems()
    try TotemsChanged()
    SetDetail("Removed the " name " Totem from the schedule.")
}

; On start every totem is due within a few seconds, staggered.
ScheduleTotems() {
    for i, t in Totems
        t.next := A_TickCount + 4000 + (i - 1) * 3000
}

TotemDue() {
    if !Cfg["TotemAuto"]
        return false
    for t in Totems
        if (t.on && t.slot != "" && A_TickCount >= t.next)
            return true
    return false
}

RunTotems() {
    for t in Totems {
        if !Running
            return
        if !(t.on && t.slot != "" && A_TickCount >= t.next)
            continue
        if (t.night && !IsNight()) {
            sd := 0
            for s in Totems
                if (s.name = "Sundial" && s.slot != "")
                    sd := s
            if (Cfg["TotemSundial"] && sd) {
                UseTotem(sd, "to make it night for the " t.name " Totem")
                sd.next := A_TickCount + sd.every * 60000
                Nap(6000)
            }
            if !IsNight() {
                t.next := A_TickCount + 120000
                LogEvent("The " t.name " Totem waits for night (sky level " SkyLevel() ")")
                continue
            }
        }
        UseTotem(t)
        t.next := A_TickCount + t.every * 60000
    }
}

UseTotem(t, why := "") {
    SetPhase("job", "Using the " t.name " Totem", why != "" ? "Used " why "." : "Hotbar key " KeyName(t.slot) ", then back to the rod.")
    ReleaseMouse()
    MouseToCenter()
    Send "{" t.slot "}"
    Nap(500)
    Click()
    Nap(Cfg["TotemWait"])
    Send "{" Cfg["RodKey"] "}"
    Nap(500)
    LogEvent("Used the " t.name " Totem")
    Alert("totem", "Used the **" t.name " Totem**" (why != "" ? " " why : "") ".")
}

; Average brightness (0-255) of the sky: a grid of points across the top of
; the Roblox window. Lower means darker.
SkyLevel() {
    cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0
    if !cr
        return -1
    sum := 0, n := 0, hr := Hud.Rect()          ; the small panel isn't sky
    for fy in [0.03, 0.06, 0.09] {
        Loop 8 {
            x := cr.x + Round(cr.w * (A_Index - 0.5) / 8), y := cr.y + Round(cr.h * fy)
            if (hr && x >= hr.x && x < hr.x + hr.w && y >= hr.y && y < hr.y + hr.h)
                continue
            c := PixelGetColor(x, y)
            sum += (((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) / 8, n++
        }
    }
    return n ? Round(sum / n) : -1
}

IsNight() => (lv := SkyLevel()) >= 0 && lv < Cfg["NightLevel"]

UseTotemsNow(*) {
    global Running, RobloxHwnd
    if (Running || AqManual)
        return SetDetail("Stop fishing first; totems run by themselves between catches.")
    if !(RobloxHwnd := FindRoblox())
        return SetPhase("error", "Roblox isn't open", "Open Fisch first, then try again.")
    try WinActivate("ahk_id " RobloxHwnd)
    Sleep 300
    Running := true
    try {
        for t in Totems
            t.next := 0
        RunTotems()
    } finally {
        Running := false
        SetPhase("idle", "Totems used", IdleHint())
    }
}

;------------------------------------------------------------------------------
; Sovereign recharge. A Sovereign enchant drains as you fish. Every N reels
; this opens the inventory, searches for a plain Enchant Relic (no mutation,
; so mutated relics are never spent), holds it, and clicks Enchant Rod and
; Confirm, once per relic. Every step checks the game responded: the
; inventory opened, the confirm box appeared, the confirm box closed. No
; setup: the buttons' spots come from Fisch's own layout (UiSpots).
;------------------------------------------------------------------------------
SovereignDue() => Cfg["SovAuto"] && SovReels >= Cfg["SovEvery"]

; A spot in Fisch's interface, in screen pixels, for this Roblox window.
UiSpot(name, cr) {
    s := UiSpots[name]
    return {x: cr.x + Round(cr.w / 2 + s[1] * cr.h), y: cr.y + Round(s[2] * cr.h)}
}

RunSovereign() {
    if IsGuest()
        return
    global SovReels, SovLast
    SovReels := 0
    cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0
    if !cr
        return
    er := UiSpot("enchantRod", cr), sr := UiSpot("search", cr), fi := UiSpot("firstItem", cr), cf := UiSpot("confirm", cr)
    SetPhase("job", "Recharging Sovereign power", "Inventory, plain relic, Enchant Rod, Confirm.")
    ReleaseMouse()
    done := 0, problem := "", opened := false
    ref := PixelGetColor(er.x, er.y)
    Send "{" Cfg["SovInvKey"] "}"
    if !WaitPixelChange(er.x, er.y, ref, Max(1500, Cfg["SovOpenWait"] * 3)) {
        problem := "the inventory didn't open"
    } else {
        opened := true
        Nap(Cfg["SovOpenWait"] // 3)
        ; find a relic with no mutation
        typed := SearchInventory(sr, cr, "mutation:no Enchant Relic")
        if !typed
            problem := "couldn't type into the inventory search"
        Loop (typed ? Cfg["SovCount"] : 0) {
            if !Running
                break
            Click(fi.x, fi.y)                       ; hold the first plain relic
            Nap(Cfg["SovStep"])
            ref := PixelGetColor(cf.x, cf.y)
            Click(er.x, er.y)                       ; Enchant Rod
            if !WaitPixelChange(cf.x, cf.y, ref, 3500) {
                problem := "Enchant Rod didn't open the confirm box (out of plain relics?)"
                break
            }
            Nap(250)
            dlg := PixelGetColor(cf.x, cf.y)
            Click(cf.x, cf.y)                       ; Confirm
            if !WaitPixelChange(cf.x, cf.y, dlg, 3000) {
                problem := "the confirm box didn't close"
                break
            }
            done++
            Nap(Cfg["SovStep"])
        }
    }
    if opened
        Send "{" Cfg["SovInvKey"] "}"              ; close the inventory
    Nap(400)
    Send "{" Cfg["RodKey"] "}"
    Nap(500)
    MouseToCenter()
    result := done " of " Cfg["SovCount"] " recharge" (Cfg["SovCount"] = 1 ? "" : "s") (problem != "" ? ", " problem : "")
    SovLast := FormatTime(, "HH:mm") ", " result
    LogEvent("Sovereign recharge: " result)
    Alert(problem != "" ? "error" : "sovereign", "Sovereign recharge: " result ".", problem != "")
    try PaintSovStatus()
}

WaitPixelChange(x, y, ref, ms) {
    t0 := A_TickCount
    while (A_TickCount - t0 < ms) {
        if (ColDist(PixelGetColor(x, y), ref) > 40)
            return true
        Sleep 50
    }
    return false
}

RechargeNow(*) {
    global Running, SovReels, RobloxHwnd
    if (Running || AqManual)
        return SetDetail("Stop fishing first; recharges run by themselves between catches.")
    if !(RobloxHwnd := FindRoblox())
        return SetPhase("error", "Roblox isn't open", "Open Fisch first, then try again.")
    try WinActivate("ahk_id " RobloxHwnd)
    Sleep 300
    Running := true
    try RunSovereign()
    finally {
        Running := false
        SetPhase("idle", "Recharge finished", SovLast)
        try PaintSovStatus()
    }
}

;------------------------------------------------------------------------------
; Discord alerts through a webhook. Messages queue and send in the
; background, so the reel loop never waits on the network.
;------------------------------------------------------------------------------

HookUrlOk(url) {
    return RegExMatch(url, "i)^https://(canary\.|ptb\.)?(discord|discordapp)\.com/api/webhooks/\d+/[\w-]+") || (HookAllowLocal && RegExMatch(url, "^http://127\.0\.0\.1:\d+/"))
}

Alert(kind, msg, shot := false) {
    global HookQueue
    if IsGuest()                                ; Discord alerts need a Discord sign-in
        return
    if (Cfg["HookUrl"] = "" || !HookUrlOk(Cfg["HookUrl"]))
        return
    if (HookKinds.Has(kind) && !Cfg[HookKinds[kind]])
        return
    if (HookQueue.Length >= 20)
        HookQueue.RemoveAt(1)
    HookQueue.Push({kind: kind, msg: msg, shot: shot && Cfg["HookShots"], when: A_NowUTC})
    SetTimer(HookPump, -20)
}

HookPump() {
    global HookReq, HookBusy, HookLast, HookItem
    if (HookBusy || !HookQueue.Length)
        return
    it := HookQueue.RemoveAt(1), HookItem := it
    body := HookBody(it, &ctype)
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", Cfg["HookUrl"], true)
        req.SetRequestHeader("Content-Type", ctype)
        req.SetTimeouts(5000, 5000, 10000, 15000)
        req.Send(body)
        HookReq := req, HookBusy := A_TickCount
        SetTimer(HookPoll, 100)
    } catch as e {
        HookLast := "Couldn't reach Discord: " e.Message
        try PaintHookStatus()
    }
}

HookPoll() {
    global HookReq, HookBusy, HookLast
    ; Status throws until the answer arrives. (WaitForResponse(0) can miss a
    ; finished request, so it isn't used.) A failed connection never
    ; answers, so it ends in the timeout.
    st := 0
    try st := HookReq.Status
    if !st {
        if (A_TickCount - HookBusy > 20000) {
            try HookReq.Abort()
            HookLast := "Couldn't reach Discord (no answer in 20 s)"
            HookDone(1500)
        }
        return
    }
    if (st = 429) {
        ; rate limited: put the message back at the front and wait as asked
        wait := 2000
        try wait := Max(500, Round(HookReq.GetResponseHeader("Retry-After") * 1000))
        if (IsObject(HookItem) && (HookItem.tries := (HookItem.HasOwnProp("tries") ? HookItem.tries : 0) + 1) <= 3)
            HookQueue.InsertAt(1, HookItem)
        HookLast := "Discord asked to slow down; retrying"
        return HookDone(wait)
    }
    HookLast := (st >= 200 && st < 300) ? "Sent " FormatTime(, "HH:mm:ss") : "Discord refused the message (HTTP " st ")"
    HookDone(1100)
}

HookDone(nextIn) {
    global HookReq, HookBusy
    HookReq := 0, HookBusy := 0
    SetTimer(HookPoll, 0)
    try PaintHookStatus()
    if HookQueue.Length
        SetTimer(HookPump, -nextIn)
}

; JSON (or multipart with a screenshot) for one alert, as UTF-8 bytes.
HookBody(it, &ctype) {
    title := HookTitles.Has(it.kind) ? HookTitles[it.kind] : "Fisch macro"
    user := RegExReplace(Cfg["HookUser"], "\D")
    ping := (user != "" && (it.kind = "error" || it.kind = "disconnect")) ? "<@" user ">" : ""
    rod := IsObject(CurRod) ? CurRod.name : "no rod yet"
    stamp := FormatTime(it.when, "yyyy-MM-dd'T'HH:mm:ss") ".000Z"
    embed := '{"title":' JsonStr(title) ',"description":' JsonStr(it.msg) ',"color":' (it.kind = "error" || it.kind = "disconnect" ? 16777215 : 9211020)
        . ',"fields":[{"name":"Casts","value":"' Stats.casts '","inline":true},{"name":"Reels","value":"' Stats.reels '","inline":true},{"name":"Rod","value":' JsonStr(rod) ',"inline":true}]'
        . ',"footer":{"text":' JsonStr(APP_NAME " " APP_VER) '},"timestamp":"' stamp '"'
    png := 0
    if it.shot {
        path := A_Temp "\fisch_alert.png"
        if (cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0) {
            hbm := CaptureBitmap(cr.x, cr.y, cr.w, cr.h)
            if SavePng(hbm, path)
                png := FileRead(path, "RAW")
            DllCall("DeleteObject", "Ptr", hbm)
        }
    }
    if png
        embed .= ',"image":{"url":"attachment://roblox.png"}'
    embed .= "}"
    json := '{"username":"FISCHXR","content":' JsonStr(ping) ',"embeds":[' embed ']'
        . (ping != "" ? ',"allowed_mentions":{"users":["' user '"]}' : ',"allowed_mentions":{"parse":[]}') "}"
    if !png {
        ctype := "application/json"
        return Utf8Array(json)
    }
    bd := "fischmacro" A_TickCount
    ctype := "multipart/form-data; boundary=" bd
    head := "--" bd "`r`nContent-Disposition: form-data; name=`"payload_json`"`r`nContent-Type: application/json`r`n`r`n" json
        . "`r`n--" bd "`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"roblox.png`"`r`nContent-Type: image/png`r`n`r`n"
    tail := "`r`n--" bd "--`r`n"
    hn := StrPut(head, "UTF-8") - 1, tn := StrPut(tail, "UTF-8") - 1
    all := Buffer(hn + png.Size + tn)
    StrPut(head, all, hn, "UTF-8")
    DllCall("RtlMoveMemory", "Ptr", all.Ptr + hn, "Ptr", png, "UPtr", png.Size)
    StrPut(tail, all.Ptr + hn + png.Size, tn, "UTF-8")
    return BytesArray(all, all.Size)
}

Utf8Array(s) {
    n := StrPut(s, "UTF-8") - 1
    b := Buffer(Max(1, n))
    StrPut(s, b, n, "UTF-8")
    return BytesArray(b, n)
}

BytesArray(buf, n) {
    arr := ComObjArray(0x11, n)
    pv := NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr")
    DllCall("RtlMoveMemory", "Ptr", pv, "Ptr", buf, "UPtr", n)
    return arr
}

JsonStr(s) {
    out := '"'
    Loop Parse, s {
        c := A_LoopField, o := Ord(c)
        if (c = '"')
            out .= '\"'
        else if (c = "\")
            out .= "\\"
        else if (o = 10)
            out .= "\n"
        else if (o = 13)
            out .= "\r"
        else if (o = 9)
            out .= "\t"
        else if (o < 32 || o > 126)
            out .= Format("\u{:04x}", o)
        else
            out .= c
    }
    return out '"'
}

SendTestAlert(*) {
    global HookLast
    if (Cfg["HookUrl"] = "") {
        HookLast := "Paste your webhook link first"
        return PaintHookStatus()
    }
    if !HookUrlOk(Cfg["HookUrl"]) {
        HookLast := "That isn't a Discord webhook link"
        return PaintHookStatus()
    }
    HookLast := "Sending…"
    PaintHookStatus()
    Alert("test", "Alerts are working. You'll hear from this channel when fishing stops, errors or disconnects.", Cfg["HookShots"] && RobloxHwnd)
}

SummaryTick() {
    if !Running
        return
    mins := Round((A_TickCount - Stats.start) / 60000)
    rate := mins ? Round(Stats.reels * 60 / mins) : 0
    Alert("summary", Format("{} casts and {} reels in {} min, about {} reels an hour. {} missed bites.", Stats.casts, Stats.reels, mins, rate, Stats.misses))
}

;------------------------------------------------------------------------------
; Auto-reconnect. Watches Roblox's own log for a lost connection (ignoring
; teleports, which also disconnect briefly), or the window closing, then
; closes Roblox, opens the rejoin link and resumes fishing.
;------------------------------------------------------------------------------
RobloxLogDirs() {
    la := EnvGet("LOCALAPPDATA")
    return [la "\Roblox\logs", la "\Packages\ROBLOXCORPORATION.ROBLOX_55nm5eh3cm0pr\LocalState\logs"]
}

NewestRobloxLog() {
    best := "", bt := 0
    for dir in (LogDirOverride != "" ? [LogDirOverride] : RobloxLogDirs())
        Loop Files, dir "\*.log" {
            t := A_LoopFileTimeModified + 0       ; YYYYMMDDHH24MISS as a number
            if (t > bt)
                bt := t, best := A_LoopFileFullPath
        }
    return best
}

; Reads what Roblox has written since the last look. A disconnect line with
; no teleport or join around it, and no rejoin within LogConfirmMs (12 s), is
; a real drop.
CheckRobloxLog() {
    global LogFile, LogPos, LogPending, LogJoinT, LogTeleT, LogLastLine
    static lastScan := 0
    if (A_TickCount - lastScan > 20000 || LogFile = "") {
        lastScan := A_TickCount
        f := NewestRobloxLog()
        if (f != LogFile) {
            LogFile := f, LogPending := 0
            LogPos := -1
        }
    }
    if (LogFile = "")
        return ""
    try {
        fo := FileOpen(LogFile, "r", "UTF-8-RAW")
        size := fo.Length
        if (LogPos < 0 || size < LogPos)
            LogPos := size          ; start at the end: old history doesn't count
        fo.Pos := LogPos
        text := fo.Read()
        LogPos := fo.Pos
        fo.Close()
    } catch
        return ""
    now := A_TickCount
    Loop Parse, text, "`n", "`r" {
        ln := A_LoopField
        if (ln = "")
            continue
        if RegExMatch(ln, "i)initiateTeleport|teleporting|TeleportService")
            LogTeleT := now
        else if RegExMatch(ln, "i)! Joining game|Connection accepted from|serverId:|Replicator created")
            LogJoinT := now
        else if RegExMatch(ln, "i)Lost connection with reason|Disconnect reason|Sending disconnect with reason|Client:Disconnect|Connection lost|Time to disconnect replication data|kicked from") {
            LogLastLine := Trim(SubStr(RegExReplace(ln, "^\S+\s*"), 1, 160))
            if (now - LogTeleT > 30000 && !LogPending)
                LogPending := now
        }
    }
    if (LogPending && LogJoinT > LogPending)
        LogPending := 0          ; it came back by itself (a teleport or server hop)
    if (LogPending && now - LogPending >= LogConfirmMs) {
        LogPending := 0
        return LogLastLine != "" ? "Roblox log: " LogLastLine : "Roblox reported a lost connection"
    }
    return ""
}

WatchConnection() {
    if (!Running || !Cfg["AutoReconnect"] || ReconnectWhy != "")
        return
    if (RobloxHwnd && !WinExist("ahk_id " RobloxHwnd))
        return FlagDisconnect("The Roblox window closed")
    if ((why := CheckRobloxLog()) != "")
        FlagDisconnect(why)
}

FlagDisconnect(why) {
    global ReconnectWhy
    if (ReconnectWhy = "")
        ReconnectWhy := why
}

ReconnectDue() => Cfg["AutoReconnect"] && ReconnectWhy != "" && !IsGuest()

; Turns whatever link the user pasted into something Windows can open.
RejoinTarget() {
    link := Trim(Cfg["RejoinLink"])
    if (link = "")
        link := Defaults["RejoinLink"]
    if RegExMatch(link, "i)^roblox(-player)?:")
        return link
    if RegExMatch(link, "^\d+$")
        return "roblox://experiences/start?placeId=" link
    if RegExMatch(link, "i)roblox\.com/games/(\d+)", &g) {
        uri := "roblox://experiences/start?placeId=" g[1]
        if RegExMatch(link, "i)privateServerLinkCode=([\w-]+)", &c)
            uri .= "&linkCode=" c[1]
        return uri
    }
    return link                  ; share links open through the browser
}

Reconnect() {
    global ReconnectWhy, RobloxHwnd, ReconnectTimes, LogFile
    why := ReconnectWhy
    ReleaseMouse()
    ; attempts in the last hour
    kept := []
    for t in ReconnectTimes
        if (A_TickCount - t < 3600000)
            kept.Push(t)
    ReconnectTimes := kept
    if (ReconnectTimes.Length >= Cfg["RejoinMax"]) {
        StopMacro("Disconnected. Gave up after " Cfg["RejoinMax"] " rejoins this hour.")
        ReconnectWhy := ""
        return false
    }
    ReconnectTimes.Push(A_TickCount)
    LogEvent("Disconnected: " why)
    Alert("disconnect", "Disconnected: " why ". Rejoining now.", true)
    SetPhase("pause", "Reconnecting", why)
    Loop 3
        try ProcessClose("RobloxPlayerBeta.exe")
    Sleep 2500
    target := RejoinTarget()
    try {
        if IsObject(RejoinHook)
            RejoinHook.Call(target)
        else
            Run(target)
    } catch as e {
        StopMacro("Couldn't open the rejoin link: " e.Message)
        ReconnectWhy := ""
        return false
    }
    SetPhase("pause", "Rejoining Fisch", "Waiting for the Roblox window.")
    t0 := A_TickCount, h := 0
    while (Running && A_TickCount - t0 < 120000) {
        if (h := FindRoblox())
            break
        Sleep 1000
    }
    if !Running
        return false
    if !h {
        LogEvent("Roblox didn't reopen; trying again")
        return true              ; ReconnectWhy is still set, so the loop retries
    }
    RobloxHwnd := h, LogFile := ""
    SetPhase("pause", "Rejoining Fisch", "Giving the game " Cfg["RejoinWait"] " s to load.")
    if !Nap(Cfg["RejoinWait"] * 1000)
        return false
    try WinActivate("ahk_id " h)
    Sleep 500
    if Cfg["RejoinResume"] {
        MouseToCenter()
        Click()
        Sleep 600
        Send "{" Cfg["RodKey"] "}"
        Sleep 700
    }
    ReconnectWhy := ""
    LogEvent("Rejoined after: " why)
    Alert("reconnect", "Rejoined Fisch and resumed fishing. If you spawned away from your spot, fishing may fail until you walk back.", true)
    return true
}

; Reconnect tab: what the watcher can see right now.
ReconnectStatusText() {
    f := NewestRobloxLog()
    if (f = "")
        return "No Roblox log found yet. It appears once Roblox has run."
    SplitPath(f, &name)
    t := FileGetTime(f, "M")
    ago := DateDiff(A_Now, t, "Seconds")
    s := "Watching " name ", updated " (ago < 90 ? ago " s" : Round(ago / 60) " min") " ago."
    if (LogLastLine != "")
        s .= "`nLast disconnect line: " LogLastLine
    return s
}

;------------------------------------------------------------------------------
; Reel-end records: what the macro saw when it decided a reel was over. A
; screenshot of the Roblox window, the reel band when the reel first looked
; gone and at the end, and the last frames' readings. The last ten are kept.
;------------------------------------------------------------------------------
SaveReelSnapshot(b, geo, p, trail, lostHbm, lostAt, reason, dur := 0, good := 0) {
    dir := A_ScriptDir "\Snapshots\Reels"
    try DirCreate(dir)
    stamp := FormatTime(, "yyyy-MM-dd_HH-mm-ss") "_" A_MSec
    cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0
    if cr {
        hbm := CaptureBitmap(cr.x, cr.y, cr.w, cr.h)
        SavePng(hbm, dir "\" stamp "_window.png")
        DllCall("DeleteObject", "Ptr", hbm)
    }
    hbm := BandCopy(b)
    SavePng(hbm, dir "\" stamp "_band_end.png")
    DllCall("DeleteObject", "Ptr", hbm)
    if lostHbm
        SavePng(lostHbm, dir "\" stamp "_band_lost.png")
    r := APP_NAME " " APP_VER " reel-end record " stamp "`n`n"
        . "Why it ended: " reason "`n"
        . "First looked gone: " (lostAt >= 0 ? lostAt " ms into the reel" : "never") "`n"
        . "Reel length: " dur " ms, frames with the reel seen: " good "`n"
        . Format("Band: {}x{} at {},{} (margin {}, reel height {})", b.w, b.h, geo.x, geo.y, geo.m, geo.ih) "`n"
        . Format("Reel box: {:.4f} {:.4f} {:.4f} {:.4f}", Cfg["ReelX1"], Cfg["ReelY1"], Cfg["ReelX2"], Cfg["ReelY2"]) "`n"
        . (cr ? "Roblox window: " cr.w "x" cr.h "`n" : "")
    if IsObject(p)
        r .= "`nLook: " p.name " (" p.id ")" (p.lib != "" ? ", library " p.lib : "") ", bar " p.barW
            . "`nTrack: " HexJoin(p.track) "`nBar: " HexJoin(p.bar) "`nFish: " HexJoin(p.fish)
            . "`nOutline rows: " p.edgeT " / " p.edgeB "`n"
    r .= "`nLast frames: ms into reel, outline (1 found, 0 missing, -1 not learned), colours fit,`n"
        . "bar (found, left-right), fish (found, x), counted as present, mouse held`n"
    for l in trail
        r .= l "`n"
    try FileAppend(r, dir "\" stamp "_report.txt", "UTF-8")
    ; keep the last ten
    stamps := []
    Loop Files, dir "\*_report.txt"
        stamps.Push(SubStr(A_LoopFileName, 1, 23))
    if (stamps.Length > 10) {
        s := ""
        for t in stamps
            s .= t "`n"
        list := StrSplit(Sort(RTrim(s, "`n")), "`n")
        Loop list.Length - 10 {
            old := list[A_Index]
            Loop Files, dir "\" old "_*.*"
                try FileDelete(A_LoopFileFullPath)
        }
    }
}

;------------------------------------------------------------------------------
; Typing into Fisch's inventory search. Roblox drops keys sent in one burst,
; so each key is held briefly with a gap, the way a person types. First it
; makes sure the box has focus: clearing it (or, if it was empty, typing a
; space) must change what the box shows. If nothing changes, nothing more is
; typed, since letters that miss the box would reach the game as hotkeys.
;------------------------------------------------------------------------------
SearchInventory(sr, cr, query) {
    Click(sr.x, sr.y)
    Nap(300)
    before := BoxSig(sr, cr)
    TypeKeys("{End}{Backspace 40}")
    Nap(200)
    now := BoxSig(sr, cr)
    if !SigDiffers(before, now) {
        TypeKeys("{Space}")
        Nap(200)
        if !SigDiffers(now, BoxSig(sr, cr))
            return false
        TypeKeys("{Backspace}")
    }
    TypeKeys(RegExReplace(query, "[{}^+!#]", "{$0}"))
    TypeKeys("{Enter}")
    Nap(700)
    return true
}

TypeKeys(keys) {
    SetKeyDelay(45, 30)
    SendEvent keys
    SetKeyDelay(10, -1)
}

; Brightness at points along the search box, to tell whether it changed.
BoxSig(sr, cr) {
    v := [], x0 := sr.x - Round(0.07 * cr.h), x1 := sr.x + Round(0.07 * cr.h)
    Loop 16 {
        c := PixelGetColor(x0 + Round((x1 - x0) * (A_Index - 1) / 15), sr.y)
        v.Push((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) / 8)
    }
    return v
}

SigDiffers(a, b) {
    n := 0
    for i, x in a
        n += Abs(x - b[i]) > 30
    return n >= 2
}

;------------------------------------------------------------------------------
; Updates and changelog. UpdateUrl points at a small file (update.json):
;   {"version": "4.1.1", "url": "https://.../FischMacro.ahk",
;    "sha256": "<64 hex digits>", "notes": "What changed..."}
; On opening (and on request) the macro reads it; if the version is newer it
; shows the notes and, if you accept, downloads the new file, checks its
; SHA-256 against the manifest, keeps the old file as .bak and restarts.
; The fingerprint is taken with Windows line endings turned into plain ones,
; so it matches however Git stored the file. Whoever controls that address
; controls what gets installed, so it belongs on an account with two-factor
; sign-in.
;------------------------------------------------------------------------------
VersionNewer(a, b) {
    pa := StrSplit(RegExReplace(a, "[^\d.]"), "."), pb := StrSplit(RegExReplace(b, "[^\d.]"), ".")
    Loop Max(pa.Length, pb.Length) {
        x := (A_Index <= pa.Length && pa[A_Index] != "") ? Integer(pa[A_Index]) : 0
        y := (A_Index <= pb.Length && pb[A_Index] != "") ? Integer(pb[A_Index]) : 0
        if (x != y)
            return x > y
    }
    return false
}

HttpGet(url, &status, binary := false, timeoutMs := 8000) {
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("GET", url, false)
    req.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
    req.SetRequestHeader("Cache-Control", "no-cache")
    req.SetRequestHeader("User-Agent", "FISCHXR/" APP_VER)
    req.Send()
    status := req.Status
    if !binary
        return req.ResponseText
    body := req.ResponseBody
    n := body.MaxIndex() + 1
    buf := Buffer(Max(1, n))
    if (n > 0)
        DllCall("RtlMoveMemory", "Ptr", buf, "Ptr", NumGet(ComObjValue(body), 8 + A_PtrSize, "Ptr"), "UPtr", n)
    return buf
}

; The string value of "key" in a flat JSON object, unescaped.
JsonField(json, key) {
    if !RegExMatch(json, '"' key '"\s*:\s*"((?:[^"\\]|\\.)*)"', &m)
        return ""
    s := m[1], out := "", i := 1, n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = "\" && i < n) {
            e := SubStr(s, i + 1, 1)
            if (e = "u")
                out .= Chr(Integer("0x" SubStr(s, i + 2, 4))), i += 6
            else
                out .= (e = "n" ? "`n" : e = "t" ? "`t" : e = "r" ? "" : e), i += 2
        } else
            out .= c, i++
    }
    return out
}

Sha256Hex(buf, n := -1) {
    n := n < 0 ? buf.Size : n, alg := 0, h := 0
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &alg, "WStr", "SHA256", "Ptr", 0, "UInt", 0)
    DllCall("bcrypt\BCryptCreateHash", "Ptr", alg, "Ptr*", &h, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0)
    DllCall("bcrypt\BCryptHashData", "Ptr", h, "Ptr", buf, "UInt", n, "UInt", 0)
    out := Buffer(32, 0)
    DllCall("bcrypt\BCryptFinishHash", "Ptr", h, "Ptr", out, "UInt", 32, "UInt", 0)
    DllCall("bcrypt\BCryptDestroyHash", "Ptr", h)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", alg, "UInt", 0)
    s := ""
    Loop 32
        s .= Format("{:02x}", NumGet(out, A_Index - 1, "UChar"))
    return s
}

; {version, url, sha256, notes} from the update link, or text saying why not.
UpdateInfo() {
    url := Trim(Cfg["UpdateUrl"])
    if (url = "")
        return "Updates aren't set up yet: paste an update link on the Settings tab."
    if !(RegExMatch(url, "i)^https://") || (UpdAllowLocal && RegExMatch(url, "^http://127\.0\.0\.1:\d+/")))
        return "The update link has to start with https://"
    try txt := HttpGet(url, &st)
    catch as e
        return "Couldn't reach the update link."
    if (st != 200)
        return "The update link answered HTTP " st "."
    v := JsonField(txt, "version"), u := JsonField(txt, "url"), h := StrLower(JsonField(txt, "sha256"))
    if (v = "" || u = "" || !RegExMatch(h, "^[0-9a-f]{64}$"))
        return "The update file is missing its version, download link or SHA-256."
    return {version: v, url: u, sha256: h, notes: JsonField(txt, "notes")}
}

UpdateNote(msg) {
    global UpdLast
    UpdLast := msg
    if (UiReady && CurTab = "Settings")
        try UI.desc.Text := msg
}

CheckForUpdate(quiet := false, *) {
    if !quiet
        UpdateNote("Checking for updates…")
    info := UpdateInfo()
    if !IsObject(info) {
        UpdateNote(info)
        if !quiet
            Dialog.Show("Updates", info, "Close")
        return
    }
    if !VersionNewer(info.version, APP_VER) {
        UpdateNote("You have the latest version (" APP_VER ").")
        if !quiet
            Dialog.Show("Updates", "You have the latest version (" APP_VER ").", "Close")
        return
    }
    UpdateNote("Version " info.version " is available.")
    if (quiet && Running)
        return
    Dialog.Show("Update to " info.version "?", (info.notes != "" ? info.notes "`n`n" : "")
        . "The macro downloads it, checks its fingerprint, keeps your current file as a backup and restarts."
        , "Update now", (*) => ApplyUpdate(info), "Later")
}

; Downloads, verifies and installs an update. True when installed.
ApplyUpdate(info, target := "", restart := true) {
    target := target != "" ? target : A_ScriptFullPath
    if Running
        StopMacro()
    try buf := HttpGet(info.url, &st, true, 30000)
    catch
        return UpdateFailed("Couldn't download the update.")
    if (st != 200)
        return UpdateFailed("The download answered HTTP " st ".")
    if (Sha256Hex(NormalizeEol(buf)) != info.sha256)
        return UpdateFailed("The download didn't match its SHA-256 fingerprint, so it wasn't used.")
    head := Buffer(4001, 0)
    DllCall("RtlMoveMemory", "Ptr", head, "Ptr", buf, "UPtr", Min(4000, buf.Size))
    if !InStr(StrGet(head, "UTF-8"), "#Requires AutoHotkey v2")
        return UpdateFailed("The download isn't an AutoHotkey v2 script, so it wasn't used.")
    try {
        f := FileOpen(target ".new", "w")
        f.RawWrite(buf, buf.Size)
        f.Close()
        if FileExist(target)
            FileCopy(target, target ".bak", true)
        FileMove(target ".new", target, true)
    } catch
        return UpdateFailed("Couldn't replace the macro file.")
    UpdateNote("Updated to " info.version ". The previous version is kept as a .bak file.")
    LogEvent("Updated to " info.version)
    if restart
        Reload()
    return true
}

; The bytes with every CR-LF turned into LF, for the fingerprint.
NormalizeEol(buf) {
    sz := buf.Size, out := Buffer(Max(1, sz)), n := 0, i := 0
    while (i < sz) {
        c := NumGet(buf, i, "UChar")
        if !(c = 13 && i + 1 < sz && NumGet(buf, i + 1, "UChar") = 10)
            NumPut("UChar", c, out, n++)
        i++
    }
    out.Size := Max(1, n)
    return out
}

UpdateFailed(msg) {
    UpdateNote(msg)
    try LogEvent("Update: " msg)
    return false
}

; What changed, newest first. Shown once after an upgrade, and on request.
ChangelogText() {
    return "
(
4.9.2
- The "Sign in to use" panel on locked pages sits on the page instead of under the sidebar.

4.9.1
- The sign-in screen's buttons work (the background was catching every click).
- Totems are open to guests.
- Rods page: type your rod's name (Enter or Use); small mistakes are fixed ("inions air" is Pinion's Aria). It stays until you press Auto.
- Rod names read from the hotbar are corrected the same way.

4.9.0
- A new sign-in screen, drawn to the FISCHXR design: the new logo, the Inter typeface (built in), a glowing Discord button that brightens when you point at it, and the minimize and close buttons in the corner.

4.8.1
- The sign-in screen is the whole program until you choose: the main window stays hidden and nothing starts until you log in with Discord or continue as a guest. Signing out returns to it.

4.8.0
- Sign in with Discord: FISCHXR asks at start (or continue as a guest). Signing in opens the FISCHXR Discord server.
- Guests can fish; Discord alerts, auto-reconnect, the aquarium, totems and Sovereign need a Discord sign-in.
- The sign-in is remembered (encrypted for your Windows account) and shown in Settings, where you can sign out.

4.7.0
- Everything moves smoothly: one animation engine eases every movement in the background, so nothing makes the window wait.
- Switches: on/off settings are sliding switches with a soft-shadowed knob.
- Depth: soft shadows where the sidebar and status line meet the page; the opened sidebar floats with rounded corners and a shadow.
- Motion: buttons fade on hover, pages glide in, the status fades in when it changes, counters flash as they rise, the window and dialogs fade in, the fishing panel glides in, and the status dot breathes while fishing. All of it is off with Reduce motion.

4.6.1
- The sidebar is quick again. Its animations run in the background instead of making the window wait, it's only repositioned when the window has moved, it opens once the mouse rests on it (not when passing over), and switching tabs only repaints what changed.

4.6.0
- New look: the sidebar is a narrow strip of icons that opens to the full sidebar when the mouse is on it. The window is narrower to match.
- More movement: the sidebar opens and shuts smoothly, the active tab's mark slides between tabs, dialogs fade in, and the status dot breathes while fishing (all off with Reduce motion).
- What's new scrolls in a box of fixed size.
- Apollo's Sunshot is supported (its charge meter fills on its own as the bar is steered).
- All rods: the bar is followed as it changes size during a reel. Before, a bar that grew or shrank a lot could be taken for scenery and the reel ended early.

4.5.3
- All rods: with the fish near either end, the bar is held against that end instead of bouncing off it.
- Verdant Oath: the bar is no longer lost at either end of the reel (a block partly out of view is still read), or during the red flash.

4.5.2
- Verdant Oath: the reel is read by its shape: the two brown blocks give the bar, the gap between them is the green zone, and the grey fish is found above and below them. The fish is aimed at the middle of the zone.

4.5.1
- Requiem: no shake inputs once its reel appears, and inputs at least 200 ms apart (Requiem lost the fish to fast inputs).
- All rods: no shake input on a frame where a reel is showing.

4.5.0
- Requiem is supported: its teal bar and dark fish are read by their own shape, and the mouse is never pressed or released faster than every 120 ms, since fast inputs snap Requiem's line.

4.4.9
- Pinion's Aria without a skin: the bright red bar is read (it was taken for the reel ending), and other cyan things nearby are no longer taken for the fish.
- All rods: steadier. A fish reading far from where the fish just was is ignored unless the next one agrees, and with the fish well inside the bar the bar is held still instead of chasing the exact centre.

4.4.8
- Pinion's Aria without a skin now works: its pale tube, pastel or red bar and cyan-topped fish are read by their own shape.
- Pinion's Aria (both looks): the bar is followed as it widens with caught notes and narrows with missed ones, instead of being lost.
- Pinion's Aria: the splash at the start of a reel is no longer taken for falling notes.

4.4.7
- Pinion's Aria notes: the whole screen above the bar is watched, so every note is followed from where it appears, about a second before it lands, and where and when it will land is known.

4.4.6
- Pinion's Aria notes: seen about a second before they land (was a fifth of a second). The bar keeps the fish and leans toward the note, then leaves just in time to catch it, covering both when they fit.
- Pinion's Aria bar: its width is taken from recent readings and held closely, so its position is steadier.

4.4.5
- Noiseform and Pinion's Aria: a reel no longer ends early while it's still up (their reels were being checked for an outline they don't have).
- A Noiseform or Pinion's Aria reel now needs both its bar and its fish to start, so dock planks and other straight lines aren't taken for a reel.

4.4.4
- Pinion's Aria: the bar is still found when it turns red (the fish outside it), so a reel is no longer taken for over, or not noticed at all, while the bar is red. The 水 symbol on the bar is no longer mistaken for the fish.

4.4.3
- Noiseform at night: the bar, fish and zones are read against the darker scene, the zone finder looks where the bar actually is, and a zone warning can't be overridden by a false one.

4.4.2
- After a Noiseform zone or a Pinion's Aria note, the bar goes straight back to the fish: switching what the bar aims at no longer upsets the fish's tracking.

4.4.1
- Noiseform: zones no longer confuse where the bar is. A zone drawn over the bar hid one of its sides, and lines in the zone's picture were read as the bar, so the bar was pushed past the right zone.

4.4.0
- Noiseform zones: the warning that flashes in the middle of the screen is read (black triangle, green circle or grey square), and the bar is taken to the matching zone before the beam strikes.

4.3.1
- Noiseform: the reel is found wherever your reel area sits on it. If a reel still isn't recognized, the Detection log says why and a picture is saved to Snapshots\Unmatched.

4.3.0
- Pinion's Aria: the bar is read by its end caps, and it catches the falling notes while keeping the fish.
- The rod name read from your hotbar now decides the reel style. A failed read keeps the last rod, so Noiseform no longer switches to Verdant Oath.

4.2.3
- Check for updates now shows its answer, and hover help shows on every page again.

4.2.2
- Updates now come from the FISCHXR page on GitHub: the macro checks when it opens and asks before installing.

4.2.1
- Noiseform: the reel is read by its shape (the bar's black sides and the fish's black capsule), so it keeps working when the bar turns dark with the fish outside it.

4.2.0
- Now called FISCHXR. Your settings carry over.
- Reads the rod in your hotbar and uses its built-in reel style. Nothing about rods is learned or saved, so no more duplicate rods.
- Verdant Oath: aims the fish at the green zone.
- Pages slide in, the panel slides in from the edge, and the text is plainer.

4.1.0
- New look: tabs down the side and a window about a third smaller.
- While fishing, a small panel in the top-right corner shows what's happening, with a Stop button.
- Simpler pages. Fine-tuning moved under Advanced: Rods, Live, Reel, Timing, More.
- Sovereign recharge types into the inventory search the way a person does, and checks the text arrived before going on.
- Updates: set an update link and the macro can update itself, checking each download's fingerprint.
)"
}

ShowWhatsNew(*) => Dialog.Show("What's new in " APP_VER, ChangelogText(), "Close", 0, "", 250)

; Once per version: note it, and show What's new after an upgrade.
WhatsNewCheck() {
    last := Cfg["LastVersion"]
    if (last = APP_VER)
        return
    Cfg["LastVersion"] := APP_VER
    Save("LastVersion")
    if (last = "" && !WasExistingIni)
        return                              ; a fresh install
    ShowWhatsNew()
}

;------------------------------------------------------------------------------
; The equipped rod, read from the hotbar. The rod's slot (the rod key) is
; captured, enlarged and read by Windows' built-in text reader (run through
; PowerShell in the background, so fishing never waits on it). Enchant names
; come first on the label and are removed, leaving the rod's own name, which
; picks the built-in reel style.
;------------------------------------------------------------------------------
RodEnchants() {
    static list := 0
    if !list {
        names := "Immortal Might|Magnitude Might|Swift Might|Steady Crown|Glimmering Crown|Stonewake Crown"
            . "|Menacing Spirit|Starforged Spirit|Propensity Spirit|Blood Reckoning|Blessed Song|Sea Overlord"
            . "|Sea Prince|Sea King|Pharaoh's Curse|Pharaohs Curse|Swift|Hasty|Hunter|Lucky|Divine|Breezed|Storming"
            . "|Controlled|Resilient|Quality|Unbreakable|Long|Steady|Blessed|Mutated|Ghastly|Noir|Abyssal|Insight"
            . "|Clever|Scrapper|Wormhole|Sacrificial|Scavenger|Chaotic|Flashline|Chronos|Momentum|Immortal|Mystical"
            . "|Ferocious|Anomalous|Quantum|Piercing|Invincible|Herculean|Overclocked|Tenacity|Tryhard|Wise|Cryogenic"
            . "|Glittered|Vicious|Dune|Restricted|Fractured|Greed|Putrid|Rage|Weak|Wobbly|Tropical|Paradise|Beached"
            . "|Valentine's|Valentines|Cupid|Santa|Gingerbread|Merry|Peppermint|Frightful|Spooky|Eerie|Sanctified"
        s := ""
        for n in StrSplit(names, "|")
            s .= Format("{:03}", 100 - StrLen(n)) "`t" n "`n"
        list := []
        for ln in StrSplit(Sort(RTrim(s, "`n")), "`n")
            list.Push(StrSplit(ln, "`t")[2])       ; longest first
    }
    return list
}

; The rod's name from its hotbar label: the slot number, stack counts and
; weights go, then enchant names are taken off the front. A name is never
; stripped down to just "Rod", so "Lucky Rod" or "Steady Rod" survive.
ParseRodName(text) {
    t := RegExReplace(text, "[\r\n\t]+", " ")
    t := RegExReplace(t, "i)\bx\s?\d+\b", " ")
    t := RegExReplace(t, "i)\b\d+(\.\d+)?\s*k?g\b", " ")
    t := RegExReplace(t, "[^A-Za-z' ]", " ")
    t := Trim(RegExReplace(t, "\s+", " "))
    loop {
        hit := false
        for e in RodEnchants() {
            n := StrLen(e)
            if (StrLen(t) > n + 1 && SubStr(t, 1, n + 1) = e " ") {
                rest := LTrim(SubStr(t, n + 2))
                if (rest = "Rod" || rest = "")
                    continue
                t := rest, hit := true
                break
            }
        }
        if !hit
            break
    }
    return t
}

; Edit distance, for names the text reader got slightly wrong.
EditDistance(a, b) {
    a := StrLower(a), b := StrLower(b), la := StrLen(a), lb := StrLen(b)
    prev := []
    Loop lb + 1
        prev.Push(A_Index - 1)
    Loop la {
        i := A_Index, cur := [i], ca := SubStr(a, i, 1)
        Loop lb {
            j := A_Index
            cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + (ca = SubStr(b, j, 1) ? 0 : 1)))
        }
        prev := cur
    }
    return prev[lb + 1]
}

; The built-in reel style for a rod name ("" means: find it from the reel).
RodLibFor(name) {
    if (name = "")
        return ""
    plain := (t) => RegExReplace(StrLower(t), "[^a-z ]")
    for lib in RodLib
        if (lib.id != "standard" && (EditDistance(name, lib.name) <= Max(1, StrLen(lib.name) // 8)
            || InStr(plain(name), plain(lib.name))))           ; a skin or unknown word in front
            return lib.id
    return "standard"
}

; The rod's hotbar slot on screen, from Fisch's layout (measured at 4K).
RodSlotRect(cr, slot) {
    k := Clamp(Integer(slot), 1, 9)
    cx := cr.x + cr.w / 2 + (k - 5) * 0.04798 * cr.h, cy := cr.y + 0.9755 * cr.h, half := 0.0235 * cr.h
    return {x: Round(cx - half), y: Round(cy - half), w: Round(2 * half), h: Round(2 * half)}
}

; Starts reading the equipped rod's name. The result lands in CurRodName.
ReadRodName(announce := false, *) {
    global RodReadBusy, RodReadAt
    if RodReadBusy
        return
    h := (RobloxHwnd && WinExist("ahk_id " RobloxHwnd)) ? RobloxHwnd : FindRoblox()
    cr := h ? ClientRect(h) : 0
    if !cr
        return RodNameDone("", "Roblox isn't open")
    slot := RegExMatch(Cfg["RodKey"], "^[1-9]$") ? Cfg["RodKey"] : 1
    r := RodSlotRect(cr, slot)
    png := A_Temp "\fischxr_rod.png", out := A_Temp "\fischxr_rod.txt"
    hbm := CaptureBitmap(r.x, r.y, r.w, r.h)
    big := 0, bmp := 0
    if Gdip.Start() {
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &bmp)
        big := GpScaled(bmp, r.w * 3, r.h * 3, 0)          ; bigger text reads better
        DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
    }
    ok := SavePng(big ? big : hbm, png)
    DllCall("DeleteObject", "Ptr", hbm)
    if big
        DllCall("DeleteObject", "Ptr", big)
    if !ok
        return RodNameDone("", "couldn't capture the hotbar")
    RodReadAt := A_TickCount
    if IsObject(OcrHook)                                     ; tests
        return RodNameDone(OcrHook.Call(png), "")
    try FileDelete(out)
    ps := OcrScript()
    try {
        Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps '" "' png '" "' out '"', , "Hide")
    } catch {
        return RodNameDone("", "Windows' text reader isn't available")
    }
    RodReadBusy := true
    SetTimer(RodNamePoll, 200)
}

RodNamePoll() {
    global RodReadBusy
    if FileExist(A_Temp "\fischxr_rod.txt") {
        Sleep 60
        txt := ""
        try txt := FileRead(A_Temp "\fischxr_rod.txt", "UTF-8")
        SetTimer(RodNamePoll, 0), RodReadBusy := false
        return RodNameDone(txt, "")
    }
    if (A_TickCount - RodReadAt > 15000) {
        SetTimer(RodNamePoll, 0), RodReadBusy := false
        RodNameDone("", "the text reader didn't answer")
    }
}

RodNameDone(text, problem) {
    global CurRodName, CurRodLib, RodReadLast, RodReadBusy
    RodReadBusy := false
    name := problem = "" ? ParseRodName(text) : ""
    if (name != "")
        name := FixRodName(name).name                ; "inions air" -> Pinion's Aria
    RodReadLast := problem != "" ? "Couldn't read the rod: " problem "." : name = "" ? "Couldn't read a rod name in the rod's hotbar slot." : ""
    if (Cfg["RodManual"] != "") {                   ; the typed rod stays in use
        if (name != "")
            RodReadLast := "The hotbar shows " name ". Your typed rod is in use; press Auto to use the hotbar."
        try RodsChanged()
        return
    }
    ; a failed read keeps the last good name: the rod doesn't change because
    ; the text reader missed once
    if (name != "" && name != CurRodName) {
        CurRodName := name, CurRodLib := RodLibFor(name)
        LogEvent("Rod: " name)
    }
    try RodsChanged()
    try Hud.Update()
}

; The PowerShell script that runs Windows' text reader on an image.
OcrScript() {
    path := A_Temp "\fischxr_ocr.ps1"
    if FileExist(path)
        return path
    FileAppend("
(
param([string]$img, [string]$out)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation``1' })[0]
    function Await($op, $type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
    $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($img)) ([Windows.Storage.StorageFile])
    $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    ($result.Lines | ForEach-Object { $_.Text }) -join [Environment]::NewLine | Set-Content -Path $out -Encoding UTF8
} catch {
    '' | Set-Content -Path $out -Encoding UTF8
}
)", path, "UTF-8")
    return path
}

; A picture of a reel no built-in style fitted, at most one a minute, the
; last ten kept in Snapshots\Unmatched, so it can be looked at later.
SaveUnmatched(b) {
    global UnmatchedAt
    if (A_TickCount - UnmatchedAt < 60000)
        return
    UnmatchedAt := A_TickCount
    dir := A_ScriptDir "\Snapshots\Unmatched"
    try {
        DirCreate(dir)
        name := dir "\" FormatTime(, "yyyy-MM-dd_HH-mm-ss") ".png"
        if SavePng(b.bmp, name)
            LogVision("Saved a picture of it: Snapshots\Unmatched")
        files := []
        Loop Files, dir "\*.png"
            files.Push(A_LoopFileFullPath)
        while (files.Length > 10)
            FileDelete(files.RemoveAt(1))
    }
}


;==============================================================================
; Discord sign-in. The browser signs in on Discord's own page and is sent back
; to a small listener on this PC (127.0.0.1 only), whose page hands the login
; to the macro. Only the "identify" permission is asked for; no password or
; client secret is involved. The login is kept encrypted for this Windows
; user, and checked with Discord at each start.
;==============================================================================
IsGuest() => AuthState.mode != "discord"
TabLocked(name) {
    if !IsGuest()
        return false
    for t in GUEST_TABS
        if (t = name)
            return true
    return false
}
UnixNow() => DateDiff(A_NowUTC, "19700101000000", "Seconds")
SaveAuth() {
    for k in ["AuthMode", "AuthTok", "AuthExp", "AuthName", "AuthId"]
        try Save(k)
}

; At start: true when the program can open signed in (a remembered sign-in
; that Discord still accepts, or one that can't be checked while offline).
AuthGate() {
    if AuthTest.noPrompt                        ; (a test harness: set as the macro loads)
        return true
    if (Cfg["AuthMode"] = "discord" && Cfg["AuthTok"] != "" && Cfg["AuthExp"] > UnixNow() + 60) {
        tok := Unprotect(Cfg["AuthTok"])
        if (tok != "") {
            me := DiscordMe(tok, &status)
            if IsObject(me)
                return (SignedIn(me, tok, Cfg["AuthExp"], false), true)
            if (status = 0 && Cfg["AuthName"] != "")    ; offline: the remembered sign-in holds until it expires
                return (SignedIn({id: Cfg["AuthId"], name: Cfg["AuthName"]}, tok, Cfg["AuthExp"], false), true)
        }
    }
    return false
}

SignedIn(me, tok, exp, fresh) {
    AuthState.mode := "discord", AuthState.id := me.id, AuthState.name := me.name
    Cfg["AuthMode"] := "discord", Cfg["AuthTok"] := Protect(tok), Cfg["AuthExp"] := exp
    Cfg["AuthName"] := me.name, Cfg["AuthId"] := me.id
    SaveAuth()
    if fresh {
        LogEvent("Signed in with Discord as " me.name)
        if AuthTest.noBrowser
            AuthTest.opened := DISCORD_INVITE
        else
            try Run(DISCORD_INVITE)              ; the FISCHXR Discord server
    }
    ApplyAuth()
}

SignOut(prompt := true) {
    AuthState.mode := prompt ? "" : "guest", AuthState.id := "", AuthState.name := ""
    for k in ["AuthMode", "AuthTok", "AuthName", "AuthId"]
        Cfg[k] := ""
    Cfg["AuthExp"] := 0
    SaveAuth()
    LogEvent("Signed out")
    if prompt
        Login.Show(CurTab)                          ; back to the sign-in screen
    else
        ApplyAuth()
}

ApplyAuth() {
    PaintAccount()
    if (UiReady && IsObject(MainGui) && Pages.Has(CurTab))
        SwitchTab(CurTab, false)
}

; Who the token belongs to: {id, name}, or 0. status is the HTTP status (0 = no answer).
DiscordMe(tok, &status := 0) {
    status := 0
    if AuthTest.me {
        f := AuthTest.me
        me := f(tok)
        status := IsObject(me) ? 200 : 401
        return me
    }
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", "https://discord.com/api/v10/users/@me", false)
        req.SetTimeouts(5000, 5000, 5000, 5000)
        req.SetRequestHeader("Authorization", "Bearer " tok)
        req.SetRequestHeader("User-Agent", "FISCHXR/" APP_VER)
        req.Send()
        status := req.Status
        if (status != 200)
            return 0
        js := req.ResponseText, id := JsonField(js, "id"), nm := JsonField(js, "global_name")
        if (nm = "")
            nm := JsonField(js, "username")
        return id != "" ? {id: id, name: nm} : 0
    }
    return 0
}

; Encrypts text for this Windows user (DPAPI), as base64, and back.
Protect(text) {
    if (text = "")
        return ""
    n := StrPut(text, "UTF-8") - 1, src := Buffer(n + 1), StrPut(text, src, "UTF-8")
    blobIn := Buffer(16, 0), blobOut := Buffer(16, 0)
    NumPut("UInt", n, blobIn, 0), NumPut("Ptr", src.Ptr, blobIn, 8)
    if !DllCall("crypt32\CryptProtectData", "Ptr", blobIn, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", blobOut)
        return ""
    cb := NumGet(blobOut, 0, "UInt"), pb := NumGet(blobOut, 8, "Ptr")
    DllCall("crypt32\CryptBinaryToString", "Ptr", pb, "UInt", cb, "UInt", 0x40000001, "Ptr", 0, "UInt*", &chars := 0)
    out := Buffer(chars * 2)
    DllCall("crypt32\CryptBinaryToString", "Ptr", pb, "UInt", cb, "UInt", 0x40000001, "Ptr", out, "UInt*", &chars)
    DllCall("LocalFree", "Ptr", pb)
    return StrGet(out)
}
Unprotect(b64) {
    if (b64 = "")
        return ""
    if !DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n := 0, "Ptr", 0, "Ptr", 0)
        return ""
    raw := Buffer(n)
    DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", raw, "UInt*", &n, "Ptr", 0, "Ptr", 0)
    blobIn := Buffer(16, 0), blobOut := Buffer(16, 0)
    NumPut("UInt", n, blobIn, 0), NumPut("Ptr", raw.Ptr, blobIn, 8)
    if !DllCall("crypt32\CryptUnprotectData", "Ptr", blobIn, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", blobOut)
        return ""
    cb := NumGet(blobOut, 0, "UInt"), pb := NumGet(blobOut, 8, "Ptr")
    text := StrGet(pb, cb, "UTF-8")
    DllCall("LocalFree", "Ptr", pb)
    return text
}

; "%41+b" -> "A b"
UrlDecode(s) {
    s := StrReplace(s, "+", " "), out := Buffer(StrPut(s, "UTF-8") + 1), n := 0, i := 1, L := StrLen(s)
    while (i <= L) {
        c := SubStr(s, i, 1)
        if (c = "%" && RegExMatch(SubStr(s, i + 1, 2), "^[0-9A-Fa-f]{2}$")) {
            NumPut("UChar", Integer("0x" SubStr(s, i + 1, 2)), out, n)
            n += 1, i += 3
        } else {
            n += StrPut(c, out.Ptr + n, "UTF-8") - 1
            i += 1
        }
    }
    return StrGet(out, n, "UTF-8")
}

class DiscordAuth {
    static sock := 0, client := 0, buf := "", state := "", t0 := 0, cT := 0, ticker := 0, whenDone := 0

    ; Opens Discord's sign-in page and waits for the browser to come back.
    ; whenDone(ok, tokenOrMessage, expiresIn) is called once.
    static Begin(whenDone) {
        this.Stop()
        this.whenDone := whenDone
        if !this.Listen()
            return this.Finish(false, "Couldn't start the sign-in listener (port " DISCORD_PORT " is in use). Close other copies of FISCHXR and try again.")
        this.state := AuthTest.state != "" ? AuthTest.state : Format("{:08x}{:08x}", Random(0, 0x7FFFFFFF), Random(0, 0x7FFFFFFF))
        url := "https://discord.com/oauth2/authorize?client_id=" DISCORD_CLIENT_ID "&response_type=token"
            . "&redirect_uri=http%3A%2F%2F127.0.0.1%3A" DISCORD_PORT "%2Fcallback&scope=identify&state=" this.state
        if !AuthTest.noBrowser
            try Run(url)
        this.t0 := A_TickCount
        if !this.ticker
            this.ticker := ObjBindMethod(this, "Poll")
        SetTimer(this.ticker, 100)
    }

    static Listen() {
        static started := false
        if !started {
            if DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", Buffer(408, 0))
                return false
            started := true
        }
        s := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
        if (s = -1)
            return false
        addr := Buffer(16, 0)
        NumPut("UShort", 2, addr, 0), NumPut("UShort", DllCall("ws2_32\htons", "UShort", DISCORD_PORT, "UShort"), addr, 2)
        NumPut("UInt", 0x0100007F, addr, 4)                                  ; 127.0.0.1 only
        if (DllCall("ws2_32\bind", "Ptr", s, "Ptr", addr, "Int", 16) != 0 || DllCall("ws2_32\listen", "Ptr", s, "Int", 4) != 0) {
            DllCall("ws2_32\closesocket", "Ptr", s)
            return false
        }
        DllCall("ws2_32\ioctlsocket", "Ptr", s, "UInt", 0x8004667E, "UInt*", 1)   ; non-blocking
        this.sock := s
        return true
    }

    static Poll() {
        if !this.sock
            return SetTimer(this.ticker, 0)
        if (A_TickCount - this.t0 > 180000)
            return this.Finish(false, "Discord didn't answer within 3 minutes. Try again.")
        if !this.client {
            c := DllCall("ws2_32\accept", "Ptr", this.sock, "Ptr", 0, "Ptr", 0, "Ptr")
            if (c = -1)
                return
            this.client := c, this.buf := "", this.cT := A_TickCount
        }
        b := Buffer(8192)
        n := DllCall("ws2_32\recv", "Ptr", this.client, "Ptr", b, "Int", 8192, "Int", 0)
        if (n > 0)
            this.buf .= StrGet(b, n, "UTF-8")
        else if (n = 0 || A_TickCount - this.cT > 3000)
            return this.Drop()
        if !InStr(this.buf, "`r`n`r`n")
            return
        path := RegExMatch(this.buf, "^GET (\S+)", &m) ? m[1] : ""
        this.Handle(path)
    }

    static Handle(path) {
        if (SubStr(path, 1, 9) = "/callback") {
            this.Reply(this.Page())
        } else if (SubStr(path, 1, 6) = "/token") {
            q := Map()
            for part in StrSplit(SubStr(path, InStr(path, "?") + 1), "&")
                if (p := InStr(part, "="))
                    q[SubStr(part, 1, p - 1)] := UrlDecode(SubStr(part, p + 1))
            this.Reply("ok", "text/plain")
            if q.Has("error")
                return this.Finish(false, "Discord sign-in was cancelled.")
            if !q.Has("access_token")
                return
            if (!q.Has("state") || q["state"] != this.state)
                return this.Finish(false, "That sign-in didn't come from this window. Try again.")
            return this.Finish(true, q["access_token"], q.Has("expires_in") ? Integer(q["expires_in"]) : 604800)
        } else
            this.Reply("Not found", "text/plain", "404 Not Found")
    }

    ; The page Discord sends the browser to: it passes the sign-in (which the
    ; browser keeps after "#", out of any server's reach) to this listener.
    static Page() {
        return '<!doctype html><html><head><meta charset="utf-8"><title>FISCHXR</title></head>'
            . '<body style="margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#111214;color:#f2f3f5;font-family:Segoe UI,sans-serif">'
            . '<div style="text-align:center"><h2 id="t">Signing you in...</h2><p id="s" style="color:#949ba4"></p></div><script>'
            . 'var h=location.hash.substring(1);history.replaceState(null,"","/callback");'
            . 'fetch("/token?"+h).then(function(){var e=new URLSearchParams(h).get("error");'
            . 'document.getElementById("t").textContent=e?"Sign-in cancelled":"Signed in";'
            . 'document.getElementById("s").textContent=e?"You can close this tab and try again from FISCHXR.":"You can close this tab and go back to FISCHXR.";});'
            . '</script></body></html>'
    }

    static Reply(body, type := "text/html; charset=utf-8", code := "200 OK") {
        n := StrPut(body, "UTF-8") - 1, bb := Buffer(n + 1), StrPut(body, bb, "UTF-8")
        head := "HTTP/1.1 " code "`r`nContent-Type: " type "`r`nContent-Length: " n "`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
        hn := StrPut(head, "UTF-8") - 1, hb := Buffer(hn + 1), StrPut(head, hb, "UTF-8")
        DllCall("ws2_32\send", "Ptr", this.client, "Ptr", hb, "Int", hn, "Int", 0)
        DllCall("ws2_32\send", "Ptr", this.client, "Ptr", bb, "Int", n, "Int", 0)
        this.Drop()
    }

    static Drop() {
        if this.client {
            DllCall("ws2_32\shutdown", "Ptr", this.client, "Int", 1)
            DllCall("ws2_32\closesocket", "Ptr", this.client)
        }
        this.client := 0, this.buf := ""
    }

    static Stop() {
        if this.ticker
            SetTimer(this.ticker, 0)
        this.Drop()
        if this.sock
            DllCall("ws2_32\closesocket", "Ptr", this.sock)
        this.sock := 0
    }

    static Finish(ok, a := "", b := 0) {
        this.Stop()
        f := this.whenDone, this.whenDone := 0
        if f
            f(ok, a, b)
    }
}

;------------------------------------------------------------------------------
; The sign-in screen: Log in with Discord, or continue as a guest. Until one is
; clicked it is the whole program: the main window is hidden, nothing starts,
; and it sits where the main window does. Drawn to the FISCHXR design (Figma,
; 540 x 416): a black gradient with fine grain, the logo, Inter type, and a
; glowing Discord button that brightens on hover.
;------------------------------------------------------------------------------
class Login {
    static g := 0, busy := false, tab := "Home", own := [], pics := Map(), label := "", statusText := "", hot := 0, minBtn := 0, closeBtn := 0

    static Show(tab := "") {
        if this.g {
            try this.g.Show()
            return
        }
        if !IsObject(MainGui)
            return
        this.tab := tab != "" ? tab : (Pages.Has(CurTab) ? CurTab : "Home")
        if (Running || AqManual)
            try StopMacro("Stopped to sign in.")
        AuthState.mode := ""                        ; nothing is usable until a choice
        ; its place: where the main window is (or would open)
        px := "", py := ""
        if DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd) {
            WinGetPos(&px, &py, , , MainGui.Hwnd)
            try Flyout.Close()
            MainGui.Hide()
        } else if (IsNumber(Cfg["WinX"]) && IsNumber(Cfg["WinY"]) && PointOnScreen(Integer(Cfg["WinX"]) + 60, Integer(Cfg["WinY"]) + 20))
            px := Integer(Cfg["WinX"]), py := Integer(Cfg["WinY"])
        g := Gui("-Caption +MinimizeBox" (Cfg["OnTop"] ? " +AlwaysOnTop" : ""), APP_NAME)
        g.BackColor := "000000", g.MarginX := 0, g.MarginY := 0
        this.g := g, this.own := [], this.pics := Map(), this.busy := false, this.hot := 0
        this.label := "Login with |Discord", this.statusText := ""
        SignArt.Start()
        ; the picture behind everything, then the parts that change over it
        this.Pic("bg", 0, 0, 540, 416, SignArt.Background(), 0x04000000)      ; (clips its siblings: no overdraw)
        this.Pic("status", 19, 230, 420, 40, SignArt.Status(""))
        this.Pic("guest", 15, 368, 160, 26, SignArt.Guest(0))
        this.Pic("btn", 292, 337, 245, 67, SignArt.Button(this.label, 0))
        Clickables[this.pics["btn"].Hwnd] := {kind: "btn", fn: (*) => Login.Start(), obj: this.pics["btn"], bg: "000000", hv: "000000", onHover: (hot) => Login.HoverBtn(hot)}
        Clickables[this.pics["guest"].Hwnd] := {kind: "btn", fn: (*) => Login.AsGuest(), obj: this.pics["guest"], bg: "000000", hv: "000000", onHover: (hot) => Login.HoverGuest(hot)}
        ; minimize and close, as on the main window
        SetFontFor(g, "norm s" FZ(HasIconFont ? 9 : 12) " c999999", HasIconFont ? "icon" : "body")
        mn := g.Add("Text", Format("x{} y0 w{} h{} Center 0x200 Background000000", ZS(460), ZS(40), ZS(30)), IconOr(Chr(0xE921), "–"))
        cl := g.Add("Text", Format("x{} y0 w{} h{} Center 0x200 Background000000", ZS(500), ZS(40), ZS(30)), IconOr(Chr(0xE8BB), "×"))
        Clickables[mn.Hwnd] := {kind: "btn", fn: (*) => WinMinimize("ahk_id " Login.g.Hwnd), obj: mn, bg: "000000", hv: "1C1C1C"}
        Clickables[cl.Hwnd] := {kind: "btn", fn: (*) => ExitApp(), obj: cl, bg: "000000", hv: "C42B1C", hvText: "FFFFFF"}
        this.own.Push(mn, cl, this.pics["btn"], this.pics["guest"])
        g.OnEvent("Close", (*) => ExitApp())
        this.minBtn := mn, this.closeBtn := cl
        ; the background goes to the back: the first control made is otherwise
        ; the one Windows finds under the mouse, and it covers the whole window
        DllCall("SetWindowPos", "Ptr", this.pics["bg"].Hwnd, "Ptr", 1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        fade := !Cfg["ReduceMotion"]
        if fade
            WinSetTransparent(0, g.Hwnd)
        g.Show((px != "" ? Format("x{} y{} ", px, py) : "") "w" ZS(540) " h" ZS(416))
        StyleWindow(g.Hwnd)
        try ApplyAppIcon(g.Hwnd)
        if fade
            FadeWindow(g.Hwnd, 220)
    }

    ; A picture control showing a drawn bitmap (the control keeps its own copy).
    static Pic(name, x, y, w, h, hbm, style := 0) {
        p := this.g.Add("Picture", Format("x{} y{} w{} h{}{}", ZS(x), ZS(y), ZS(w), ZS(h), style ? " +" style : ""), "HBITMAP:" hbm)
        this.pics[name] := p
        return p
    }
    static SetPic(name, hbm) {
        if !(this.g && this.pics.Has(name))
            return DllCall("DeleteObject", "Ptr", hbm)
        hw := this.pics[name].Hwnd
        old := SendMessage(0x172, 0, hbm, hw)                              ; STM_SETIMAGE
        cur := SendMessage(0x173, 0, 0, hw)                                ; what it shows now
        ; (Windows may show a copy of the bitmap, or the bitmap itself: only
        ; what it isn't showing is deleted)
        if (old && old != cur)
            DllCall("DeleteObject", "Ptr", old)
        if (cur != hbm)
            DllCall("DeleteObject", "Ptr", hbm)
    }

    ; The button brightens (and its glow grows) on hover, fading both ways.
    static HoverBtn(hot) {
        from := this.hot, to := hot ? 1 : 0
        step(e) {
            Login.hot := from + (to - from) * e
            Login.SetPic("btn", SignArt.Button(Login.label, Login.hot))
        }
        Anim.Run(hot ? 140 : 200, step, "signbtn")
    }
    static HoverGuest(hot) {
        this.SetPic("guest", SignArt.Guest(hot ? 1 : 0))
    }
    static SetStatus(text) {
        this.statusText := text
        this.SetPic("status", SignArt.Status(text))
    }
    static SetLabel(label) {
        this.label := label
        this.SetPic("btn", SignArt.Button(label, this.hot))
    }

    static Start() {
        if this.busy
            return
        this.busy := true
        this.SetPic("btn", SignArt.Button(this.label, this.hot, true))       ; pressed, for a moment
        this.SetLabel("Waiting for |Discord...")
        this.SetStatus("Approve FISCHXR in your browser, then come back here.")
        DiscordAuth.Begin(ObjBindMethod(this, "Done"))
    }

    static Done(ok, a := "", b := 0) {
        this.busy := false
        if !this.g
            return
        if !ok {
            this.SetLabel("Login with |Discord"), this.SetStatus(a)
            return
        }
        this.SetStatus("Checking your Discord account...")
        me := DiscordMe(a)
        if !IsObject(me) {
            this.SetLabel("Login with |Discord"), this.SetStatus("Couldn't confirm your Discord account. Try again.")
            return
        }
        SignedIn(me, a, UnixNow() + b, true)
        this.Close()
    }

    static AsGuest() {
        DiscordAuth.Stop()
        AuthState.mode := "guest"
        LogEvent("Using FISCHXR as a guest")
        this.Close()
    }

    ; The choice is made: the main window takes its place.
    static Close() {
        ; (the reference goes first: destroying the window sends it messages
        ; that would otherwise find a window half gone)
        g := this.g, this.g := 0
        for c in this.own
            if IsObject(c)
                try Clickables.Delete(c.Hwnd)          ; (its buttons go with it)
        this.own := [], this.pics := Map(), this.busy := false
        Anim.Finish("signbtn")
        px := "", py := ""
        if g {
            try WinGetPos(&px, &py, , , g.Hwnd)
            try g.Destroy()
        }
        SignArt.Release()
        ApplyAuth()
        ShowMain(this.tab, px, py)
        SetTimer(WhatsNewCheck, -600)
    }
}

;------------------------------------------------------------------------------
; Drawing the sign-in screen (GDI+), in the design's own units (540 x 416),
; scaled to the screen: text in the bundled Inter, colours and sizes as the
; design has them.
;------------------------------------------------------------------------------
class SignArt {
    static coll := 0, bufs := [], fams := Map(), logo := 0, grain := 0, backdrop := 0, s := 1.0

    static Start() {
        if !Gdip.Start()
            return false
        if !this.coll {
            DllCall("gdiplus\GdipNewPrivateFontCollection", "Ptr*", &c := 0)
            this.coll := c
            for k in ["regular", "medium", "semibold", "bold", "extrabold"]
                if (buf := B64Buffer(SignInAsset("inter-" k))) {
                    this.bufs.Push(buf)                              ; (the fonts live in this memory)
                    DllCall("gdiplus\GdipPrivateAddMemoryFont", "Ptr", c, "Ptr", buf, "Int", buf.Size)
                }
            this.logo := GpFromBase64(SignInAsset("logo")), this.grain := GpFromBase64(SignInAsset("grain"))
        }
        ; the backdrop everything is drawn over: the gradient and the grain
        this.s := ToPhys(1000) / 1000
        w := Round(540 * this.s), h := Round(416 * this.s)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &g := 0)
        rc := this.RectF(0, 0, w, h)
        DllCall("gdiplus\GdipCreateLineBrushFromRect", "Ptr", rc, "UInt", 0xFF000000, "UInt", 0xFF030303, "Int", 1, "Int", 0, "Ptr*", &br := 0)
        DllCall("gdiplus\GdipFillRectangleI", "Ptr", g, "Ptr", br, "Int", 0, "Int", 0, "Int", w, "Int", h)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
        if this.grain {
            DllCall("gdiplus\GdipCreateTexture", "Ptr", this.grain, "Int", 0, "Ptr*", &tb := 0)
            DllCall("gdiplus\GdipFillRectangleI", "Ptr", g, "Ptr", tb, "Int", 0, "Int", 0, "Int", w, "Int", h)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", tb)
        }
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
        if this.backdrop
            DllCall("gdiplus\GdipDisposeImage", "Ptr", this.backdrop)
        this.backdrop := bmp
        return true
    }
    static Release() {
        if this.backdrop
            DllCall("gdiplus\GdipDisposeImage", "Ptr", this.backdrop), this.backdrop := 0
    }

    static RectF(x, y, w, h) {
        r := Buffer(16)
        NumPut("Float", x, "Float", y, "Float", w, "Float", h, r)
        return r
    }
    ; (each weight is its own family: "Inter" -> "FXInter Regular", "Inter
    ; Medium" -> "FXInter Medium", and bold "Inter" -> "FXInter Bold")
    static Family(name) {
        name := name = "Inter" ? "FXInter Regular" : StrReplace(name, "Inter ", "FXInter ")
        if this.fams.Has(name)
            return this.fams[name]
        f := 0
        if this.coll
            DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", name, "Ptr", this.coll, "Ptr*", &f)
        if !f                                                   ; (Inter missing: Segoe UI)
            DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &f)
        return this.fams[name] := f
    }

    ; A canvas for the design area x, y, w, h, with the backdrop already in it.
    static Canvas(x, y, w, h) {
        s := this.s, pw := Round(w * s), ph := Round(h * s)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", pw, "Int", ph, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &g := 0)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", g, "Int", 4)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 4)
        DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", g, "Ptr", this.backdrop, "Int", 0, "Int", 0, "Int", pw, "Int", ph
            , "Int", Round(x * s), "Int", Round(y * s), "Int", pw, "Int", ph, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
        return {bmp: bmp, g: g, x: x, y: y}
    }
    static Done(c) {
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", c.g)
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", c.bmp, "Ptr*", &hbm := 0, "UInt", 0xFF000000)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", c.bmp)
        return hbm
    }

    ; Text in the design's units: fam is an Inter face ("Inter", "Inter Medium",
    ; ...), style 0 plain / 1 bold / 4 underlined, alpha 0-255 of white.
    static Text(c, str, fam, px, style, alpha, x, y, w, h, align := 0, valign := 0, rgb := 0xFFFFFF) {
        s := this.s
        if (style & 1)
            fam := "Inter Bold", style &= ~1
        DllCall("gdiplus\GdipCreateFont", "Ptr", this.Family(fam), "Float", px * s, "Int", style, "Int", 2, "Ptr*", &font := 0)
        fmt := this.Format()
        DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", align)
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", valign)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", (alpha << 24) | rgb, "Ptr*", &br := 0)
        DllCall("gdiplus\GdipDrawString", "Ptr", c.g, "WStr", str, "Int", -1, "Ptr", font, "Ptr", this.RectF((x - c.x) * s, (y - c.y) * s, w * s, h * s), "Ptr", fmt, "Ptr", br)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br), DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt), DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
    }
    static TextWidth(c, str, fam, px, style) {
        if (style & 1)
            fam := "Inter Bold", style &= ~1
        DllCall("gdiplus\GdipCreateFont", "Ptr", this.Family(fam), "Float", px * this.s, "Int", style, "Int", 2, "Ptr*", &font := 0)
        fmt := this.Format()
        box := Buffer(16, 0)
        DllCall("gdiplus\GdipMeasureString", "Ptr", c.g, "WStr", str, "Int", -1, "Ptr", font, "Ptr", this.RectF(0, 0, 4000, 400), "Ptr", fmt, "Ptr", box, "Int*", 0, "Int*", 0)
        DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt), DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
        return NumGet(box, 8, "Float") / this.s
    }

    ; Text laid out without the padding GDI+ normally adds around it (Figma
    ; adds none), on one line, trailing spaces measured.
    static Format() {
        DllCall("gdiplus\GdipStringFormatGetGenericTypographic", "Ptr*", &tf := 0)
        DllCall("gdiplus\GdipCloneStringFormat", "Ptr", tf, "Ptr*", &fmt := 0)
        DllCall("gdiplus\GdipSetStringFormatFlags", "Ptr", fmt, "Int", 0x4000 | 0x1000 | 0x800)
        return fmt
    }

    ; A rounded rectangle (design units, relative to the canvas).
    static RoundRect(c, x, y, w, h, r) {
        s := this.s, x := (x - c.x) * s, y := (y - c.y) * s, w *= s, h *= s, d := 2 * r * s
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &p := 0)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", p, "Float", x, "Float", y, "Float", d, "Float", d, "Float", 180, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", p, "Float", x + w - d, "Float", y, "Float", d, "Float", d, "Float", 270, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", p, "Float", x + w - d, "Float", y + h - d, "Float", d, "Float", d, "Float", 0, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", p, "Float", x, "Float", y + h - d, "Float", d, "Float", d, "Float", 90, "Float", 90)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", p)
        return p
    }

    ; Everything that doesn't change: the logo and the words.
    static Background() {
        c := this.Canvas(0, 0, 540, 416), s := this.s
        if this.logo
            DllCall("gdiplus\GdipDrawImageRectI", "Ptr", c.g, "Ptr", this.logo, "Int", Round(19 * s), "Int", Round(18 * s), "Int", Round(87 * s), "Int", Round(87 * s))
        this.Text(c, "FISCHXR", "Inter ExtraBold", 32, 0, 255, 19, 105, 400, 40)
        this.Text(c, "Sign In with Discord to unlock full access.", "Inter Medium", 13, 0, 153, 19, 144, 480, 18)
        ; the explanation: four lines, the design's tight spacing, centred on y 198
        for ln in [["Choose to either sign in the macro as a user, or guest below.", 180.5]
                , ["*Guests are unable to access all features until they login with a", 204.5]
                , ["discord account.", 216.5]]
            this.Text(c, ln[1], "Inter", 12, 0, 191, 19, ln[2] - 8, 500, 16, 0, 1)
        return this.Done(c)
    }

    ; The status line under the explanation.
    static Status(str) {
        c := this.Canvas(19, 230, 420, 40)
        if (str != "")
            this.Text(c, str, "Inter", 12, 0, 191, 19, 230, 420, 40)
        return this.Done(c)
    }

    ; "Continue as a Guest*": 60% white, 95% when the mouse is on it.
    static Guest(t) {
        c := this.Canvas(15, 368, 160, 26), s := this.s, a := Round(153 + 89 * t)
        this.Text(c, "Continue as a Guest*", "Inter", 13, 0, a, 19, 368, 160, 24, 0, 1)
        w := this.TextWidth(c, "Continue as a Guest*", "Inter", 13, 0)
        DllCall("gdiplus\GdipCreatePen1", "UInt", (a << 24) | 0xFFFFFF, "Float", Max(1, s), "Int", 2, "Ptr*", &pen := 0)
        uy := (387 - c.y) * s
        DllCall("gdiplus\GdipDrawLine", "Ptr", c.g, "Ptr", pen, "Float", (19 - c.x) * s, "Float", uy, "Float", (19 + w - c.x) * s, "Float", uy)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
        return this.Done(c)
    }

    ; The Discord button, t from 0 (resting) to 1 (under the mouse). label has
    ; its bold part after "|" ("Login with |Discord").
    static Button(label, t, pressed := false) {
        c := this.Canvas(292, 337, 245, 67), s := this.s
        ; the glow: rounded rings fading outward, blurple
        ga := Round((pressed ? 7 : 11) + 6 * t)
        loop 12 {
            i := 13 - A_Index
            p := this.RoundRect(c, 308 - i, 353 - i, 213 + 2 * i, 35 + 2 * i, 5 + i)
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", (ga << 24) | 0x5461E8, "Ptr*", &br := 0)
            DllCall("gdiplus\GdipFillPath", "Ptr", c.g, "Ptr", br, "Ptr", p)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", br), DllCall("gdiplus\GdipDeletePath", "Ptr", p)
        }
        ; the face: the design's gradient (#5865F2 to #333A8C at 79 degrees), brighter under the mouse
        c1 := pressed ? Mix("5865F2", "000000", 0.12) : Mix("5865F2", "FFFFFF", 0.10 * t)
        c2 := pressed ? Mix("333A8C", "000000", 0.12) : Mix("333A8C", "FFFFFF", 0.10 * t)
        p := this.RoundRect(c, 308, 353, 213, 35, 5)
        DllCall("gdiplus\GdipCreateLineBrushFromRectWithAngle", "Ptr", this.RectF((308 - c.x) * s, (353 - c.y) * s, 213 * s, 35 * s)
            , "UInt", 0xFF000000 | Integer("0x" c1), "UInt", 0xFF000000 | Integer("0x" c2), "Float", 79, "Int", 1, "Int", 0, "Ptr*", &br := 0)
        DllCall("gdiplus\GdipFillPath", "Ptr", c.g, "Ptr", br, "Ptr", p)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
        ; its thin light edge
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x80FFFFFF, "Float", Max(0.5, 0.5 * s), "Int", 2, "Ptr*", &pen := 0)
        DllCall("gdiplus\GdipDrawPath", "Ptr", c.g, "Ptr", pen, "Ptr", p)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen), DllCall("gdiplus\GdipDeletePath", "Ptr", p)
        ; the label, right-aligned to x 487 as designed, with a faint shadow
        parts := StrSplit(label, "|"), a := parts[1], bo := parts.Length > 1 ? parts[2] : ""
        wa := this.TextWidth(c, a, "Inter SemiBold", 16, 0), wb := bo != "" ? this.TextWidth(c, bo, "Inter", 16, 1) : 0
        x0 := 487 - wa - wb
        for sh in [[1, 64, 0x000000], [0, 255, 0xFFFFFF]] {
            this.Text(c, a, "Inter SemiBold", 16, 0, sh[2], x0, 361 + sh[1], wa + 4, 22, 0, 0, sh[3])
            if (bo != "")
                this.Text(c, bo, "Inter", 16, 1, sh[2], x0 + wa, 361 + sh[1], wb + 4, 22, 0, 0, sh[3])
        }
        return this.Done(c)
    }
}

; base64 text -> a Buffer of its bytes (or 0)
B64Buffer(b64) {
    if (b64 = "" || !DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n := 0, "Ptr", 0, "Ptr", 0))
        return 0
    buf := Buffer(n)
    DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
    return buf
}

;------------------------------------------------------------------------------
; What a guest sees on a signed-in-only page.
;------------------------------------------------------------------------------
class LockPanel {
    static ctls := [], title := 0

    static Build() {
        this.ctls := []
        ic := AddT(0, PAGE_X, 104, 48, 48, HasIconFont ? Chr(0xE72E) : "", HasIconFont ? "icon" : "body", 26, Pal.dim, Pal.content, "0x200")
        this.title := AddT(0, PAGE_X, 160, LEFT_W, 30, "", "display", 14, Pal.text, Pal.content, "0x200")
        body := AddT(0, PAGE_X, 194, LEFT_W, 44, "Discord alerts, auto-reconnect, the aquarium and Sovereign are for signed-in users. Sign in with Discord to use them.", "body", 10, Pal.dim, Pal.content)
        b := AddT(0, PAGE_X, 250, 210, 36, "Log in with Discord", "body", 10, "FFFFFF", "5865F2", "Center 0x200")
        Clickables[b.Hwnd] := {kind: "btn", fn: (*) => Login.Show(), obj: b, bg: "5865F2", hv: "4752C4"}
        this.ctls := [ic, this.title, body, b]
        for c in this.ctls
            c.Visible := false
    }

    static Show(tab) {
        for c in this.ctls
            c.Visible := (tab != "")
        if (tab != "")
            this.title.Text := "Sign in to use " tab
    }
}

;------------------------------------------------------------------------------
; Who's signed in, shown in the opened sidebar under the name.
;------------------------------------------------------------------------------
PaintAccount() {
    if !Flyout.acct
        return
    try Flyout.acct.Text := IsGuest() ? "Guest · Log in" : AuthState.name " · Log out"
}
AccountClick() {
    Flyout.Close()
    if IsGuest()
        Login.Show()
    else
        Dialog.Show("Discord account", "Signed in as " AuthState.name ".", "Log out", (*) => SignOut(), "Cancel")
}


;------------------------------------------------------------------------------
; Rod names: typed by hand on the Rods page, and read from the hotbar, are
; corrected to the nearest known Fisch rod ("inions air" -> Pinion's Aria),
; but only when one rod is clearly the nearest (a rod not in the list keeps
; the name as given, rather than becoming a different rod).
;------------------------------------------------------------------------------
KnownRods() {
    static list := 0
    if !list {
        list := StrSplit(""
            . "Carbon Rod|Fast Rod|Fischer's Rod|Flimsy Rod|Jinglestar Rod|Long Rod|Lucky Rod|Plastic Rod|Rose Rend|"
            . "Scarlet Ravager|Stone Rod|Training Rod|Fortune Rod|Fungal Rod|Magma Rod|Magnet Rod|Nocturnal Rod|"
            . "Precision Rod|Rapid Rod|Steady Rod|Arctic Rod|Avalanche Rod|Cinder Block Rod|Crystalized Rod|Depthseeker Rod|"
            . "Midas Rod|Phoenix Rod|Reinforced Rod|Scurvy Rod|Wildflower Rod|Aurora Rod|Blade Of Glorp|Brick Rod|Carrot Rod|"
            . "Champions Rod|Friendly Rod|Ice Warpers Rod|Kings Rod|Mythical Rod|Silly Fun Happy Rod|Duskwire|"
            . "Great Dreamer Rod|Rainbow Cluster Rod|Resourceful Rod|Riptide Rod|Seasons Rod|Summit Rod|Trident Rod|"
            . "Volcanic Rod|Voyager Rod|Wisdom Rod|Abyssal Specter Rod|Auric Rod|Destiny Rod|Nico's Yarncaster|"
            . "Rod Of The Depths|Rod Of The Exalted One|Scarlet Spincaster Rod|Sunken Rod|The Boom Ball|The Lost Rod|"
            . "Toxic Spire Rod|Vineweaver Rod|Challenger's Rod|Great Rod of Oscar|Heaven's Rod|Kraken Rod|"
            . "Leviathan's Fang Rod|Lucid Rod|Luminescent Oath|Merlin's Staff|No-Life Rod|Poseidon Rod|Random Rod|"
            . "Tempest Rod|Zeus Rod|Celestial Rod|Cerulean Fang Rod|Maelstrom|Rod Of The Eternal King|"
            . "Rod Of The Forgotten Fang|Wicked Fang Rod|Eidolon Rod|Elder Mossripper|Ethereal Prism Rod|Evil Pitchfork|"
            . "Rod Of The Zenith|Seraphic Rod|Spiritbinder|Onirifalx|Ruinous Oath|Tryhard Rod|Wind Elemental|Dreambreaker|"
            . "Fabulous Rod|Santa's Miracle Rod|Abaia's Spite|Anchor n' Chain|Ancient Idol Rod|Apollo's Sunshot|Artisan Rod|"
            . "Azure Of Lagoon|Bellona's Waraxe|Blazebringer Rod|Bloomspire|Boreal Rod|Breeze Caster|Brine-Infused Rod|"
            . "Chasm-Stalker|Cheeto Rod|Coral Rod|Crew Rod|Crowbar|Cryolash|Cusk Purger|Dave Rod|Daybreaker Rod|"
            . "Zeus's Thundermaul|Noiseform|Pinion's Aria|Requiem|Verdant Oath|Nate's Blade|Remembrance|Migu Rod|"
            . "Olympian Godbreaker"
            , "|")
        for lib in RodLib                          ; (the built-in reel styles' rods too)
            if (lib.id != "standard" && !InStr(lib.name, "("))
                list.Push(lib.name)
        ; each rod once (a rod listed twice would be its own runner-up, and
        ; never "clearly the nearest")
        seen := Map(), uniq := []
        for n in list
            if !seen.Has(NormRod(n))
                seen[NormRod(n)] := true, uniq.Push(n)
        list := uniq
    }
    return list
}
NormRod(t) => RegExReplace(StrLower(t), "[^a-z0-9]")

; {name, known}: the known rod a name most likely is, or the name as given.
FixRodName(raw) {
    q := NormRod(raw), lq := StrLen(q)
    if (lq < 3)
        return {name: raw, known: false}
    best := "", b1 := 9, b2 := 9
    for n in KnownRods() {
        k := NormRod(n), lk := StrLen(k)
        if (k = "")
            continue
        if (k = q)
            return {name: n, known: true}
        d := EditDistance(q, k)
        if (lq >= 5 && InStr(k, q))                ; letters lost at either end
            d := Min(d, (lk - lq) * 0.34)
        if (lk >= 5 && InStr(q, k))                ; a skin or other word around the name
            d := Min(d, (lq - lk) * 0.1)
        r := d / Max(lk, lq)
        if (r < b1)
            b2 := b1, b1 := r, best := n
        else if (r < b2)
            b2 := r
    }
    ; near enough, and clearly nearer than any other rod
    if (b1 <= 0.3 && b2 - b1 >= 0.08)
        return {name: best, known: true}
    return {name: raw, known: false}
}

; What the typed name would be, shown under the box as it's typed.
RodSuggest() {
    if !(UiReady && UI.HasOwnProp("rodMatch"))
        return
    t := Trim(UI.rodEdit.Value)
    if (t = "")
        return UI.rodMatch.Text := "Type your rod's name; small mistakes are fixed."
    fx := FixRodName(t)
    style := RodById(RodLibFor(fx.name)).name
    UI.rodMatch.Text := fx.known ? "Matches " fx.name "  ·  reel style: " style
        : "No known rod by that name; it would use the " style " reel."
}

; Uses the typed rod (corrected), until Auto is pressed.
UseTypedRod() {
    global CurRodName, CurRodLib
    t := Trim(UI.rodEdit.Value)
    if (t = "")
        return ClearTypedRod()
    name := FixRodName(t).name
    Cfg["RodManual"] := name, Save("RodManual")
    CurRodName := name, CurRodLib := RodLibFor(name)
    UI.rodEdit.Value := name
    LogEvent("Rod set by hand: " name)
    RodSuggest()
    RodsChanged()
    try Hud.Update()
}

; Back to reading the rod from the hotbar.
ClearTypedRod(reread := true) {
    global CurRodName, CurRodLib, RodReadLast
    Cfg["RodManual"] := "", Save("RodManual")
    CurRodName := "", CurRodLib := "", RodReadLast := ""
    try UI.rodEdit.Value := ""
    RodSuggest()
    RodsChanged()
    if reread
        SetTimer(ReadRodName.Bind(true), -1)
}


;==============================================================================
; Embedded images: the loading-screen logo and the app icon tile (PNG, base64).
; Kept in a function so they exist from the moment the script loads.
;==============================================================================
LogoData(which) {
    if (which = "splash")
        return "
(Join
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
)"
    return "
(Join
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
)"
}

;==============================================================================
; The sign-in screen's pictures and fonts (base64): the FISCHXR logo, a fine
; grain for the background, and the Inter typeface in the five weights the
; design uses (trimmed to the characters the macro shows, each weight named as
; its own family, "FXInter Regular" and so on, so it's found by name).
;
; Inter is by Rasmus Andersson and is bundled under the SIL Open Font License:
; Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)
;
; This Font Software is licensed under the SIL Open Font License, Version 1.1.
; This license is copied below, and is also available with a FAQ at:
; http://scripts.sil.org/OFL
;
; -----------------------------------------------------------
; SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
; -----------------------------------------------------------
;
; PREAMBLE
; The goals of the Open Font License (OFL) are to stimulate worldwide
; development of collaborative font projects, to support the font creation
; efforts of academic and linguistic communities, and to provide a free and
; open framework in which fonts may be shared and improved in partnership
; with others.
;
; The OFL allows the licensed fonts to be used, studied, modified and
; redistributed freely as long as they are not sold by themselves. The
; fonts, including any derivative works, can be bundled, embedded,
; redistributed and/or sold with any software provided that any reserved
; names are not used by derivative works. The fonts and derivatives,
; however, cannot be released under any other type of license. The
; requirement for fonts to remain under this license does not apply
; to any document created using the fonts or their derivatives.
;
; DEFINITIONS
; "Font Software" refers to the set of files released by the Copyright
; Holder(s) under this license and clearly marked as such. This may
; include source files, build scripts and documentation.
;
; "Reserved Font Name" refers to any names specified as such after the
; copyright statement(s).
;
; "Original Version" refers to the collection of Font Software components as
; distributed by the Copyright Holder(s).
;
; "Modified Version" refers to any derivative made by adding to, deleting,
; or substituting -- in part or in whole -- any of the components of the
; Original Version, by changing formats or by porting the Font Software to a
; new environment.
;
; "Author" refers to any designer, engineer, programmer, technical
; writer or other person who contributed to the Font Software.
;
; PERMISSION AND CONDITIONS
; Permission is hereby granted, free of charge, to any person obtaining
; a copy of the Font Software, to use, study, copy, merge, embed, modify,
; redistribute, and sell modified and unmodified copies of the Font
; Software, subject to the following conditions:
;
; 1) Neither the Font Software nor any of its individual components,
; in Original or Modified Versions, may be sold by itself.
;
; 2) Original or Modified Versions of the Font Software may be bundled,
; redistributed and/or sold with any software, provided that each copy
; contains the above copyright notice and this license. These can be
; included either as stand-alone text files, human-readable headers or
; in the appropriate machine-readable metadata fields within text or
; binary files as long as those fields can be easily viewed by the user.
;
; 3) No Modified Version of the Font Software may use the Reserved Font
; Name(s) unless explicit written permission is granted by the corresponding
; Copyright Holder. This restriction only applies to the primary font name as
; presented to the users.
;
; 4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
; Software shall not be used to promote, endorse or advertise any
; Modified Version, except to acknowledge the contribution(s) of the
; Copyright Holder(s) and the Author(s) or with their explicit written
; permission.
;
; 5) The Font Software, modified or unmodified, in part or in whole,
; must be distributed entirely under this license, and must not be
; distributed under any other license. The requirement for fonts to
; remain under this license does not apply to any document created
; using the Font Software.
;
; TERMINATION
; This license becomes null and void if any of the above conditions are
; not met.
;
; DISCLAIMER
; THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
; OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
; COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
; INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
; DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
; FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
; OTHER DEALINGS IN THE FONT SOFTWARE.
;==============================================================================
SignInAsset(name) {
    switch name {
        case "logo":
            return "
(Join
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
)"
        case "grain":
            return "
(Join
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
)"
        case "inter-regular":
            return "
(Join
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AGUAIABJAG4AdABlAHIAIABQAHIAbwBqAGUAYwB0ACAAQQB1AHQAaABvAHIAcwBGAFgASQBuAHQAZQByACAAUgBlAGcAdQBsAGEAcgBSAGUAZwB1AGwAYQByAEYAWABJAG4AdABlAHIALQBSAGUAZwB1AGwAYQByADsARgBJAFMAQwBIAFgAUgBWAGUAcgBzAGkAbwBuACAANAAuADAAMAAxADsAZwBpAHQALQA5ADIAMgAxAGIAZQBlAGQAMwBGAFgASQBuAHQAZQByAC0AUgBlAGcAdQBsAGEAcgBJAG4AdABlAHIAIABVAEkAIABhAG4AZAAgAEkAbgB0AGUAcgAgAGkAcwAgAGEAIAB0AHIAYQBkAGUAbQBhAHIAawAgAG8AZgAgAHIAcwBtAHMALgByAHMAbQBzAFIAYQBzAG0AdQBzACAAQQBuAGQAZQByAHMAcwBvAG4AaAB0AHQAcABzADoALwAvAHIAcwBtAHMALgBtAGUALwBUAGgAaQBzACAARgBvAG4AdAAgAFMAbwBmAHQAdwBhAHIAZQAgAGkAcwAgAGwAaQBjAGUAbgBzAGUAZAAgAHUAbgBkAGUAcgAgAHQAaABlACAAUwBJAEwAIABPAHAAZQBuACAARgBvAG4AdAAgAEwAaQBjAGUAbgBzAGUALAAgAFYAZQByAHMAaQBvAG4AIAAxAC4AMQAuACAAVABoAGkAcwAgAGwAaQBjAGUAbgBzAGUAIABpAHMAIABhAHYAYQBpAGwAYQBiAGwAZQAgAHcAaQB0AGgAIABhACAARgBB
AFEAIABhAHQAOgAgAGgAdAB0AHAAOgAvAC8AcwBjAHIAaQBwAHQAcwAuAHMAaQBsAC4AbwByAGcALwBPAEYATABoAHQAdABwADoALwAvAHMAYwByAGkAcAB0AHMALgBzAGkAbAAuAG8AcgBnAC8ATwBGAEwAAwAAAAAAAP6kAIwAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAH//wAPAAEAAAAMAAAAAAAAAAIABAABACQAAQAoADkAAQA7ADwAAQBIAEkAAQABAAAACgA8AF4ABERGTFQAGmN5cmwAJmdyZWsAJmxhdG4AJgAEAAAAAP//AAEAAQAEAAAAAP//AAEAAAACa2VybgAOa2VybgAWAAAAAgABAAAAAAAEAAEAAAABAAAAAgAGACAACQAIAAIACgASAAEAAgAABoAAAQACAAAIvAACAAgAAgAKAYQAAQA4AAQAAAAXAKQAagB4AIoApACqAMAAxgDiAOgA3ADcAOIA6AD+AP4A/gEIAQ4BIAFeAV4BaAABABcAOQA+AD8AQABCAEMATABQAFUAVgBXAFgAWQBaAFsAXABdAGAAYgBnAGgAaQBqAAMAW//JAFz/yQBd/8kABABb/7sAXP+7AF3/uwBn/6MABgA+/+wAQv/sAEP/owBN/4wAYf9GAGf+uwABAGf/owAFAFD/gABV/0YAV/+7AFj/uwBZ/0YAAQBn/68ABQBQ/5wAVf+pAFb/jABZ/6kAWv+MAAEAQ/+7AAEAQ/+AAAUAQ/91AE3/AABh/zsAZv+jAGf/rwACAD7/4wBC//IAAQBQ/68ABABA/2kAUP9pAFX/OwBZ/zsADwA5/6MAOv8jADz/owA9/4wAPv+jAD//owBB/6MAQv+jAEz/rwBPAEUAUP9eAFX/rwBZ/68AaP91AGn/dQACAEP/uwBn/3UABABV/4AAVv91AFn/gABa/3UAAgPYAAQAAAQMBHYAFgAWAAAAAAAAAAAAAAAAAAAAAAAA/4AAAAAAAAAAAAAAAAD/6f+YAAD/0gAA/7sAAAAAAAAAAAAAAAAAAAAAAAD/jAAAAAAAAAAAAAAAAAAA/3UAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/rwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA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AAAAAAAA/17/XgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP9p/2kAAAAAAAAAAAAAAAAAAAAAAAAAAP+jAAAAAAAA/7sAAAAAAAAAAAAAAAD/mAAAAAAAAAAAAAAAAAAA/6MAAAAAAAAAAAAAAAAAAAAAAAD/uwAAAAAAAAAAAAAAAP9e/2kAAAAAAAAAAP+6AAAAAAAAAAAAAP+Y/9IAAAAA/5gAAAAA/6MAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/mAAAAAAAAAAA/68AAP87/6MAAAAAAAAAAP+YAAAAAAAAAAAAAP91/7sAAAAA/4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/4wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4gAAAAAAAAAAAAAAAAAAAAAAAAAA/7sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4gAAAAAAAAAA
//YAAAAAAAAAAP/PAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/eAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/94AAAAAAAAAAAAAAAD/rwAA/7sAAAAAAAD/uwAA/68AAAAAAAD/IwAg/7v/7AAAAAD/uwAAAAAAAAAAAAAAAP+AAAD/uwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAD/0gAAAAAAAAAAAAAAAAAAAAAAAAAA/4z/owAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/6MAAAAAAAAAAAAAAAAAAAAAAAD/xgAA/7oAAAAA/4wAAAAAAAAAAAAA/6//ugAA/5j/7AAAAAD/owAAAAAAAAAAAAAAAAAAAAD/ugAAAAAAAAAAAAAAAAAAAAAAAP+6/68AAP/YAAD/7P/YAAAAAAAAAAAAAAAAAAD/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/1AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/8YAAP/SAAAAAAAA/3UAAP+7/zv/UgAAAAAAAAAAAAD/uwAAAAAAAP91AAAAAAAAAAD/xgAAAAAAAP+w/0b/Uv71AAAAAAAAAAD/owAA/3UAAAAAAAAAAAAAAAAAAAAAAAD/uwAAAAAAAAAAAAAAAP+j/7sAAAAAAAAAAP+jAAAAAAAAAAAAAP+vAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/5gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/0gAAAAAAAAAAAAAAAP/S/8MAAAAAAAAAAP/1AAAAAAAAAAAAAP/SAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9IAAAAAAAAAAAAAAAAAAAAA/7sAAAAAAAAAAAAAAAAAAAAAAAD/rwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/uwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/xAAAAAD/u/+6/+AAAAAAAAD/0gAUAAD/xgAAAAAAAAAAAAD/0gAAAAAAAAAAAAAAAAAeAAAAAP+M/4D/sAAAAAAAAAAAAAAAAAAA/4AAAAAAAAAAAAAAAAD/xgAAAAAAAAAAAAAAAAAeAAAAAAAAAAoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/0gAAAAAAAAAoAAAAAAAAAAAAAAAA/4D/0gAA/7sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2wAAAAD/dQAAAAAAAAAAAAAAAAAA/5gAAAAAAAAAAAAAAAAAAP+7AAAAAAAAAAAAAAAAAAAAAP9p/4wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/mP+6AAD/jAAA/5gAAAAAAAD/uwAAAAD/mAAA/4AAAAAAAAAAAAAAAAAAAAAAAAD/mAAAADIAAP87/4AAAAAAAAAAAAAAAAAAAAAA/7sAAAAAAAAAAAAAAAAAAAAAAAD/mAAA/7v/dAAA/5gAAAAAAAD/owAAAAD/mAAA/4AAAAAAAAD/rwAAAAAAAAAeAAD/gAAAAAD/u/87/zsAAAAAAAAAAAAA
AAAAAP/s/7sAAAAAAB4AAAAAAAD/nAAAAAD/9QAAAAD/aQAAAAAAAAAAAAAAAAAAAAD/owAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP+v/zsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/7sAAAAAAAAAAAAAAAAAAAAAAAAAAP+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/6YAAAAAAAAAAAAAAAAAAP+7/7sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/7oAHv/YAAAAAP/Y/3UAAP9p/1IAAAALAAAAAAAAAAAAAAAAAAAAAP90AAAAAP91/4wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/r//EAAD/RgAA/87/uwAA/7sAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/7sAAAAAAAAAAAAAAAAAAP+v/3UAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/ugAAAAAAAAAAAAAAAP+7/8MAAAAAAAAAAP+6AAAAAAAAAAAAAP+7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/gP/V/4z+6AAd/4z/rwAAAB3/YwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4gAAAAD/XgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/q8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/sAAAAAD/OwAAAAAAAAAAAAD/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/tIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+n/XgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/zsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/6QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAeAAAAAAAAAAAAAP+7AAAAAAAAAAAAAP+6AAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/mP+YAAD/IwAA/6MAAAAAAAD/rwAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/zsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/zgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAA0AAQAkAAAAJwA6ACQAPAA8ADgAQABCADkARQBGADwASABIAD4ASgBKAD8ATABMAEAATgBRAEEAVABgAEUAYwBmAFIAaABpAFYAbwBvAFgAAQABAG8ABQASABgABAAHACgAHAAAAAAACAAVABkAAAAAAAQAJAAEABQAEQANAAgAIwAiABcADAAdAAIAAQABAAAAAQABAB4AGwACAAkAAAAAAAkAFgAAAAIAAgABAAEAGwAKAA4ABgADAAsAIQAgAAsAEwAyADEAHwAAAC8AAAAAAAAAMwAvADEAAAAAADAALgAAAC4AAAAuAAAAKQAAADQAHwAnAA8AAAAAABoALAAqACsAKwAsACoAJgAmACYAJQAlAA8AAAAAABAADwAaAA8AAAAtAC0AAAAAAAAAAAAAAA8AAQABAHAABQABAAQAAQABAAEABAABAAEAHwABAAEAAQABAAQAAQAEAAEAEQANAAkAGAAcABIADAAVAAcAAQACAAIAAgACACAAAgABAA8AAAAAABcAAQABAAMAAwACAAMAAgADAAsABgAIAAoAGwAZAAoAFgAsACcAKQAAACoAKAAAACcALgAtAAAAAAAAACYAAAAlAAAAJQAAACUAHQAAAC8AEwArAA4AAAAAABQAIwAhACIAIgAjACEAHgAeAB4AGgAaAA4AAAAAABAADgAUAA4AAAAkACQAAAAAAAAAAAAAAAAADgAAAAEAAAAKACYAKAACREZMVAAObGF0bgAYAAQAAAAA//8AAAAAAAAAAAAAAAA=
)"
        case "inter-medium":
            return "
(Join
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dQBtAFIAZQBnAHUAbABhAHIARgBYAEkAbgB0AGUAcgAtAE0AZQBkAGkAdQBtADsARgBJAFMAQwBIAFgAUgBWAGUAcgBzAGkAbwBuACAANAAuADAAMAAxADsAZwBpAHQALQA5ADIAMgAxAGIAZQBlAGQAMwBGAFgASQBuAHQAZQByAC0ATQBlAGQAaQB1AG0ASQBuAHQAZQByACAAVQBJACAAYQBuAGQAIABJAG4AdABlAHIAIABpAHMAIABhACAAdAByAGEAZABlAG0AYQByAGsAIABvAGYAIAByAHMAbQBzAC4AcgBzAG0AcwBSAGEAcwBtAHUAcwAgAEEAbgBkAGUAcgBzAHMAbwBuAGgAdAB0AHAAcwA6AC8ALwByAHMAbQBzAC4AbQBlAC8AVABoAGkAcwAgAEYAbwBuAHQAIABTAG8AZgB0AHcAYQByAGUAIABpAHMAIABsAGkAYwBlAG4AcwBlAGQAIAB1AG4AZABlAHIAIAB0AGgAZQAgAFMASQBMACAATwBwAGUAbgAgAEYAbwBuAHQAIABMAGkAYwBlAG4AcwBlACwAIABWAGUAcgBzAGkAbwBuACAAMQAuADEALgAgAFQAaABpAHMAIABsAGkAYwBlAG4AcwBlACAAaQBzACAAYQB2AGEAaQBsAGEAYgBsAGUAIAB3AGkAdABoACAAYQAgAEYAQQBRACAAYQB0ADoAIABoAHQAdABwADoALwAvAHMAYwByAGkAcAB0AHMALgBzAGkAbAAuAG8AcgBnAC8ATwBGAEwAaAB0AHQAcAA6AC8A
LwBzAGMAcgBpAHAAdABzAC4AcwBpAGwALgBvAHIAZwAvAE8ARgBMAAADAAAAAAAA/qwAnQAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAf//AA8AAQAAAAwAAAAAAAAAAgAEAAEAJAABACgAOQABADsAPAABAEgASQABAAEAAAAKADwAXgAEREZMVAAaY3lybAAmZ3JlawAmbGF0bgAmAAQAAAAA//8AAQABAAQAAAAA//8AAQAAAAJrZXJuAA5rZXJuABYAAAACAAEAAAAAAAQAAQAAAAEAAAACAAYAIAAJAAgAAgAKABIAAQACAAAG/AABAAIAAAlwAAIACAACAAoBpgABADwABAAAABkAtADWAHIAiACaALQAugDQANYA3AD8AQIA9gD2APwBAgEYARgBGAEqATABQgGAAYABigABABkAOQA6AD4APwBAAEIAQwBMAE8AUABVAFYAVwBYAFkAWgBbAFwAXQBgAGIAZwBoAGkAagAFAFv/zABc/8wAXf/MAGj//ABp//wABABb/74AXP++AF3/vgBn/6MABgA+/+wAQv/sAEP/owBN/4wAYf9GAGf+uwABAGf/owAFAFD/gABV/0YAV/+7AFj/uwBZ/0YAAQBn/68AAQBnAAwABgBQ/5wAVf+pAFb/jABZ/6kAWv+MAGH/5gABAEP/uwABAEP/gAAFAEP/dQBN/wAAYf87AGb/owBn/68ABAA+/+gAQv/uAET/+ABu/+sAAQBQ/68ABABA/2kAUP9pAFX/OwBZ/zsADwA5/6MAOv8jADz/owA9/4wAPv+jAD//owBB/6MAQv+jAEz/rwBPAEUAUP9eAFX/rwBZ/68AaP91AGn/dQACAEP/uwBn/3UABABV/4AAVv91AFn/gABa/3UAAgQwAAQAAARkBM4AFgAYAAAAAAAAAAAAAAAAAAAAAAAAAAD/lwAAAAAAAAAAAAAAAP/t/5wAAAAA/84AAP/DAAAAAAAAAAAAAAAAAAAAAAAAAAD/jAAAAAAAAAAAAAAAAAAA/3UAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/68AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/owAA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
)"
        case "inter-semibold":
            return "
(Join
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AAsAIAG/AAMAAQQJAAwAIAG/AAMAAQQJAA0BIAHfAAMAAQQJAA4ANAL/RlhJbnRlciBTZW1pQm9sZFJlZ3VsYXJGWEludGVyLVNlbWlCb2xkO0ZJU0NIWFJGWEludGVyLVNlbWlCb2xkAEMAbwBwAHkAcgBpAGcAaAB0ACAAMgAwADEANgAgAFQAaABlACAASQBuAHQAZQByACAAUAByAG8AagBlAGMAdAAgAEEAdQB0AGgAbwByAHMARgBYAEkAbgB0AGUAcgAgAFMAZQBtAGkAQgBvAGwAZABSAGUAZwB1AGwAYQByAEYAWABJAG4AdABlAHIALQBTAGUAbQBpAEIAbwBsAGQAOwBGAEkAUwBDAEgAWABSAFYAZQByAHMAaQBvAG4AIAA0AC4AMAAwADEAOwBnAGkAdAAtADkAMgAyADEAYgBlAGUAZAAzAEYAWABJAG4AdABlAHIALQBTAGUAbQBpAEIAbwBsAGQASQBuAHQAZQByACAAVQBJACAAYQBuAGQAIABJAG4AdABlAHIAIABpAHMAIABhACAAdAByAGEAZABlAG0AYQByAGsAIABvAGYAIAByAHMAbQBzAC4AcgBzAG0AcwBSAGEAcwBtAHUAcwAgAEEAbgBkAGUAcgBzAHMAbwBuAGgAdAB0AHAAcwA6AC8ALwByAHMAbQBzAC4AbQBlAC8AVABoAGkAcwAgAEYAbwBuAHQAIABTAG8AZgB0AHcAYQByAGUAIABpAHMAIABsAGkAYwBlAG4AcwBlAGQAIAB1AG4AZABlAHIAIAB0AGgA
ZQAgAFMASQBMACAATwBwAGUAbgAgAEYAbwBuAHQAIABMAGkAYwBlAG4AcwBlACwAIABWAGUAcgBzAGkAbwBuACAAMQAuADEALgAgAFQAaABpAHMAIABsAGkAYwBlAG4AcwBlACAAaQBzACAAYQB2AGEAaQBsAGEAYgBsAGUAIAB3AGkAdABoACAAYQAgAEYAQQBRACAAYQB0ADoAIABoAHQAdABwADoALwAvAHMAYwByAGkAcAB0AHMALgBzAGkAbAAuAG8AcgBnAC8ATwBGAEwAaAB0AHQAcAA6AC8ALwBzAGMAcgBpAHAAdABzAC4AcwBpAGwALgBvAHIAZwAvAE8ARgBMAAAAAAMAAAAAAAD+tQCtAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAB//8ADwABAAAADAAAAAAAAAACAAQAAQAkAAEAKAA5AAEAOwA8AAEASABJAAEAAQAAAAoAPABeAARERkxUABpjeXJsACZncmVrACZsYXRuACYABAAAAAD//wABAAEABAAAAAD//wABAAAAAmtlcm4ADmtlcm4AFgAAAAIAAQAAAAAABAABAAAAAQAAAAIABgAgAAkACAACAAoAEgABAAIAAAb8AAEAAgAACXAAAgAIAAIACgGmAAEAPAAEAAAAGQC0ANYAcgCIAJoAtAC6ANAA1gDcAPwBAgD2APYA/AECARgBGAEYASoBMAFCAYABgAGKAAEAGQA5ADoAPgA/AEAAQgBDAEwATwBQAFUAVgBXAFgAWQBaAFsAXABdAGAAYgBnAGgAaQBqAAUAW//OAFz/zgBd/84AaP/5AGn/+QAEAFv/wABc/8AAXf/AAGf/owAGAD7/7ABC/+wAQ/+jAE3/jABh/0YAZ/67AAEAZ/+jAAUAUP+AAFX/RgBX/7sAWP+7AFn/RgABAGf/rwABAGcAGQAGAFD/nABV/6kAVv+MAFn/qQBa/4wAYf/MAAEAQ/+7AAEAQ/+AAAUAQ/91AE3/AABh/zsAZv+jAGf/rwAEAD7/7QBC/+oARP/vAG7/1gABAFD/rwAEAED/aQBQ/2kAVf87AFn/OwAPADn/owA6/yMAPP+jAD3/jAA+/6MAP/+jAEH/owBC/6MATP+vAE8ARQBQ/14AVf+vAFn/rwBo/3UAaf91AAIAQ/+7AGf/dQAEAFX/gABW/3UAWf+AAFr/dQACBDAABAAA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
)"
        case "inter-bold":
            return "
(Join
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bwBqAGUAYwB0ACAAQQB1AHQAaABvAHIAcwBGAFgASQBuAHQAZQByACAAQgBvAGwAZABSAGUAZwB1AGwAYQByAEYAWABJAG4AdABlAHIALQBCAG8AbABkADsARgBJAFMAQwBIAFgAUgBWAGUAcgBzAGkAbwBuACAANAAuADAAMAAxADsAZwBpAHQALQA5ADIAMgAxAGIAZQBlAGQAMwBGAFgASQBuAHQAZQByAC0AQgBvAGwAZABJAG4AdABlAHIAIABVAEkAIABhAG4AZAAgAEkAbgB0AGUAcgAgAGkAcwAgAGEAIAB0AHIAYQBkAGUAbQBhAHIAawAgAG8AZgAgAHIAcwBtAHMALgByAHMAbQBzAFIAYQBzAG0AdQBzACAAQQBuAGQAZQByAHMAcwBvAG4AaAB0AHQAcABzADoALwAvAHIAcwBtAHMALgBtAGUALwBUAGgAaQBzACAARgBvAG4AdAAgAFMAbwBmAHQAdwBhAHIAZQAgAGkAcwAgAGwAaQBjAGUAbgBzAGUAZAAgAHUAbgBkAGUAcgAgAHQAaABlACAAUwBJAEwAIABPAHAAZQBuACAARgBvAG4AdAAgAEwAaQBjAGUAbgBzAGUALAAgAFYAZQByAHMAaQBvAG4AIAAxAC4AMQAuACAAVABoAGkAcwAgAGwAaQBjAGUAbgBzAGUAIABpAHMAIABhAHYAYQBpAGwAYQBiAGwAZQAgAHcAaQB0AGgAIABhACAARgBBAFEAIABhAHQAOgAgAGgAdAB0AHAAOgAvAC8AcwBjAHIAaQBwAHQA
cwAuAHMAaQBsAC4AbwByAGcALwBPAEYATABoAHQAdABwADoALwAvAHMAYwByAGkAcAB0AHMALgBzAGkAbAAuAG8AcgBnAC8ATwBGAEwAAAAAAwAAAAAAAP69AL4AAAAAAAAAAAAAAAAAAAAAAAAAAAABAAH//wAPAAEAAAAMAAAAAAAAAAIABAABACQAAQAoADkAAQA7ADwAAQBIAEkAAQABAAAACgA8AF4ABERGTFQAGmN5cmwAJmdyZWsAJmxhdG4AJgAEAAAAAP//AAEAAQAEAAAAAP//AAEAAAACa2VybgAOa2VybgAWAAAAAgABAAAAAAAEAAEAAAABAAAAAgAGACAACQAIAAIACgASAAEAAgAABvwAAQACAAAJcAACAAgAAgAKAaYAAQA8AAQAAAAZALQA1gByAIgAmgC0ALoA0ADWANwA/AECAPYA9gD8AQIBGAEYARgBKgEwAUIBgAGAAYoAAQAZADkAOgA+AD8AQABCAEMATABPAFAAVQBWAFcAWABZAFoAWwBcAF0AYABiAGcAaABpAGoABQBb/9EAXP/RAF3/0QBo//UAaf/1AAQAW//DAFz/wwBd/8MAZ/+jAAYAPv/sAEL/7ABD/6MATf+MAGH/RgBn/rsAAQBn/6MABQBQ/4AAVf9GAFf/uwBY/7sAWf9GAAEAZ/+vAAEAZwAlAAYAUP+cAFX/qQBW/4wAWf+pAFr/jABh/7IAAQBD/7sAAQBD/4AABQBD/3UATf8AAGH/OwBm/6MAZ/+vAAQAPv/zAEL/5gBE/+cAbv/BAAEAUP+vAAQAQP9pAFD/aQBV/zsAWf87AA8AOf+jADr/IwA8/6MAPf+MAD7/owA//6MAQf+jAEL/owBM/68ATwBFAFD/XgBV/68AWf+vAGj/dQBp/3UAAgBD/7sAZ/91AAQAVf+AAFb/dQBZ/4AAWv91AAIEMAAEAAAEZATOABYAGAAAAAAAAAAAAAAAAAAAAAAAAAAA/8UAAAAAAAAAAAAAAAD/9f+kAAAAAP/GAAD/1AAAAAAAAAAAAAAAAAAAAAAAAAAA/4wAAAAAAAAAAAAAAAAAAP91AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP+vAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlAAAAAAAA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
)"
        case "inter-extrabold":
            return "
(Join
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AHUAbABhAHIARgBYAEkAbgB0AGUAcgAtAEUAeAB0AHIAYQBCAG8AbABkADsARgBJAFMAQwBIAFgAUgBWAGUAcgBzAGkAbwBuACAANAAuADAAMAAxADsAZwBpAHQALQA5ADIAMgAxAGIAZQBlAGQAMwBGAFgASQBuAHQAZQByAC0ARQB4AHQAcgBhAEIAbwBsAGQASQBuAHQAZQByACAAVQBJACAAYQBuAGQAIABJAG4AdABlAHIAIABpAHMAIABhACAAdAByAGEAZABlAG0AYQByAGsAIABvAGYAIAByAHMAbQBzAC4AcgBzAG0AcwBSAGEAcwBtAHUAcwAgAEEAbgBkAGUAcgBzAHMAbwBuAGgAdAB0AHAAcwA6AC8ALwByAHMAbQBzAC4AbQBlAC8AVABoAGkAcwAgAEYAbwBuAHQAIABTAG8AZgB0AHcAYQByAGUAIABpAHMAIABsAGkAYwBlAG4AcwBlAGQAIAB1AG4AZABlAHIAIAB0AGgAZQAgAFMASQBMACAATwBwAGUAbgAgAEYAbwBuAHQAIABMAGkAYwBlAG4AcwBlACwAIABWAGUAcgBzAGkAbwBuACAAMQAuADEALgAgAFQAaABpAHMAIABsAGkAYwBlAG4AcwBlACAAaQBzACAAYQB2AGEAaQBsAGEAYgBsAGUAIAB3AGkAdABoACAAYQAgAEYAQQBRACAAYQB0ADoAIABoAHQAdABwADoALwAvAHMAYwByAGkAcAB0AHMALgBzAGkAbAAuAG8AcgBnAC8ATwBGAEwAaAB0AHQAcAA6
AC8ALwBzAGMAcgBpAHAAdABzAC4AcwBpAGwALgBvAHIAZwAvAE8ARgBMAAAAAwAAAAAAAP7HANIAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAH//wAPAAEAAAAMAAAAAAAAAAIABAABACQAAQAoADkAAQA7ADwAAQBIAEkAAQABAAAACgA8AF4ABERGTFQAGmN5cmwAJmdyZWsAJmxhdG4AJgAEAAAAAP//AAEAAQAEAAAAAP//AAEAAAACa2VybgAOa2VybgAWAAAAAgABAAAAAAAEAAEAAAABAAAAAgAGACAACQAIAAIACgASAAEAAgAABvwAAQACAAAJcAACAAgAAgAKAaYAAQA8AAQAAAAZALQA1gByAIgAmgC0ALoA0ADWANwA/AECAPYA9gD8AQIBGAEYARgBKgEwAUIBgAGAAYoAAQAZADkAOgA+AD8AQABCAEMATABPAFAAVQBWAFcAWABZAFoAWwBcAF0AYABiAGcAaABpAGoABQBb/9QAXP/UAF3/1ABo//EAaf/xAAQAW//GAFz/xgBd/8YAZ/+jAAYAPv/sAEL/7ABD/6MATf+MAGH/RgBn/rsAAQBn/6MABQBQ/4AAVf9GAFf/uwBY/7sAWf9GAAEAZ/+vAAEAZwA0AAYAUP+cAFX/qQBW/4wAWf+pAFr/jABh/5IAAQBD/7sAAQBD/4AABQBD/3UATf8AAGH/OwBm/6MAZ/+vAAQAPv/5AEL/4QBE/90Abv+oAAEAUP+vAAQAQP9pAFD/aQBV/zsAWf87AA8AOf+jADr/IwA8/6MAPf+MAD7/owA//6MAQf+jAEL/owBM/68ATwBFAFD/XgBV/68AWf+vAGj/dQBp/3UAAgBD/7sAZ/91AAQAVf+AAFb/dQBZ/4AAWv91AAIEMAAEAAAEZATOABYAGAAAAAAAAAAAAAAAAAAAAAAAAAAA/+EAAAAAAAAAAAAAAAD/+v+pAAAAAP/BAAD/3gAAAAAAAAAAAAAAAAAAAAAAAAAA/4wAAAAAAAAAAAAAAAAAAP91AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP+vAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA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
)"
    }
    return ""
}

