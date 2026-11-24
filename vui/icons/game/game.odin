// Game icon set for skeuomorphic HUDs: filled 24px silhouettes authored for vinland-ui
// (crossed sword and shamshir, march chevrons, patrol pennons, heater shield with boss, eye,
// order scroll, eight-pointed khatam star, heart, nasal helm). Public domain / CC0.
package vui_icons_game

import vui "../.."

Game_Icons :: struct {
	attack: vui.Icon,
	move: vui.Icon,
	patrol: vui.Icon,
	stop: vui.Icon,
	follow: vui.Icon,
	scroll: vui.Icon,
	khatam: vui.Icon,
	heart: vui.Icon,
	helm: vui.Icon,
}

ATTACK_PATHS := [?]vui.Icon_Path{
	{d = "M20.5 2 L22 3.5 L11.2 14.3 L9.7 12.8 Z", even_odd = false},
	{d = "M7.2 11.6 L12.4 16.8 L11.3 17.9 L6.1 12.7 Z", even_odd = false},
	{d = "M8.3 15.3 L9.7 16.7 L5.4 21 L4 19.6 Z", even_odd = false},
	{d = "M2.10 20.40 A1.5 1.5 0 1 1 5.10 20.40 A1.5 1.5 0 1 1 2.10 20.40 Z", even_odd = false},
	{d = "M3 2.6 C8.5 4.2 13.3 8.2 15.2 13.7 L13.7 15.2 C11.8 10.1 7.9 6.2 3 2.6 Z", even_odd = false},
	{d = "M16.8 11.6 L18 12.8 L12.8 18 L11.6 16.8 Z", even_odd = false},
	{d = "M14.4 16.4 L15.6 17.6 L19 21 L20.4 19.6 L17 16.2 L15.8 15 Z", even_odd = false},
}
MOVE_PATHS := [?]vui.Icon_Path{
	{d = "M3 5 L10.5 12 L3 19 L6.5 19 L14 12 L6.5 5 Z", even_odd = false},
	{d = "M10 5 L17.5 12 L10 19 L13.5 19 L21 12 L13.5 5 Z", even_odd = false},
}
PATROL_PATHS := [?]vui.Icon_Path{
	{d = "M4 3 L5.6 3 L5.6 21 L4 21 Z", even_odd = false},
	{d = "M5.6 3.2 L11.5 5.4 L5.6 7.8 Z", even_odd = false},
	{d = "M18.4 3 L20 3 L20 21 L18.4 21 Z", even_odd = false},
	{d = "M18.4 3.2 L12.5 5.4 L18.4 7.8 Z", even_odd = false},
	{d = "M7.5 15.2 C9 11.6 15 11.6 16.5 15.2 L18 14.4 L17.6 18.6 L13.8 17 L15.2 16.2 C14 14 10 14 8.8 16.2 Z", even_odd = false},
}
STOP_PATHS := [?]vui.Icon_Path{
	{d = "M12 2.2 L20 5 L20 11 C20 16 16.6 19.6 12 21.8 C7.4 19.6 4 16 4 11 L4 5 Z M12 4.4 L6 6.5 L6 11 C6 14.8 8.5 17.6 12 19.5 C15.5 17.6 18 14.8 18 11 L18 6.5 Z", even_odd = true},
	{d = "M9.2 11.2 A2.8 2.8 0 1 1 14.8 11.2 A2.8 2.8 0 1 1 9.2 11.2 Z", even_odd = false},
}
FOLLOW_PATHS := [?]vui.Icon_Path{
	{d = "M12 5 C6.5 5 2.8 9.2 1.5 12 C2.8 14.8 6.5 19 12 19 C17.5 19 21.2 14.8 22.5 12 C21.2 9.2 17.5 5 12 5 Z M12 7.2 C15.7 7.2 18.6 9.9 19.9 12 C18.6 14.1 15.7 16.8 12 16.8 C8.3 16.8 5.4 14.1 4.1 12 C5.4 9.9 8.3 7.2 12 7.2 Z", even_odd = true},
	{d = "M8.60 12.00 A3.4 3.4 0 1 1 15.40 12.00 A3.4 3.4 0 1 1 8.60 12.00 Z", even_odd = false},
}
SCROLL_PATHS := [?]vui.Icon_Path{
	{d = "M6 3 L19 3 C20.7 3 21.5 4.2 21.5 5.5 C21.5 6.8 20.7 8 19 8 L18 8 L18 18.5 C18 20 17 21 15.5 21 L5 21 C3.3 21 2.5 19.8 2.5 18.5 C2.5 17.2 3.3 16 5 16 L6 16 Z M8 5 L8 16.2 C8.9 16.7 9.4 17.5 9.4 18.5 C9.4 18.7 9.4 18.8 9.3 19 L15.5 19 C15.8 19 16 18.8 16 18.5 L16 5 Z", even_odd = true},
	{d = "M10 8 L14 8 L14 9.4 L10 9.4 Z M10 11 L14 11 L14 12.4 L10 12.4 Z", even_odd = false},
}
KHATAM_PATHS := [?]vui.Icon_Path{
	{d = "M12.00 1.00 L14.37 6.27 L19.78 4.22 L17.73 9.63 L23.00 12.00 L17.73 14.37 L19.78 19.78 L14.37 17.73 L12.00 23.00 L9.63 17.73 L4.22 19.78 L6.27 14.37 L1.00 12.00 L6.27 9.63 L4.22 4.22 L9.63 6.27 Z M8.80 12.00 A3.2 3.2 0 1 0 15.20 12.00 A3.2 3.2 0 1 0 8.80 12.00 Z", even_odd = false},
}
HEART_PATHS := [?]vui.Icon_Path{
	{d = "M12 21 C5 16 2 12.5 2 8.6 C2 5.6 4.3 3.5 7 3.5 C9 3.5 10.8 4.6 12 6.4 C13.2 4.6 15 3.5 17 3.5 C19.7 3.5 22 5.6 22 8.6 C22 12.5 19 16 12 21 Z", even_odd = false},
}
HELM_PATHS := [?]vui.Icon_Path{
	{d = "M12 2 C12.6 2 13 2.5 13 3 L13 4.1 C17.4 4.7 20 8.6 20 13 L20 16 L16.5 17.5 L16.5 21 L13 21 L13 12 L11 12 L11 21 L7.5 21 L7.5 17.5 L4 16 L4 13 C4 8.6 6.6 4.7 11 4.1 L11 3 C11 2.5 11.4 2 12 2 Z", even_odd = false},
}

register :: proc(ctx: ^vui.Context) -> (ic: Game_Icons) {
	ic.attack = vui.icon_register(ctx, "game-attack", {24, 24}, ATTACK_PATHS[:])
	ic.move = vui.icon_register(ctx, "game-move", {24, 24}, MOVE_PATHS[:])
	ic.patrol = vui.icon_register(ctx, "game-patrol", {24, 24}, PATROL_PATHS[:])
	ic.stop = vui.icon_register(ctx, "game-stop", {24, 24}, STOP_PATHS[:])
	ic.follow = vui.icon_register(ctx, "game-follow", {24, 24}, FOLLOW_PATHS[:])
	ic.scroll = vui.icon_register(ctx, "game-scroll", {24, 24}, SCROLL_PATHS[:])
	ic.khatam = vui.icon_register(ctx, "game-khatam", {24, 24}, KHATAM_PATHS[:])
	ic.heart = vui.icon_register(ctx, "game-heart", {24, 24}, HEART_PATHS[:])
	ic.helm = vui.icon_register(ctx, "game-helm", {24, 24}, HELM_PATHS[:])
	return
}
