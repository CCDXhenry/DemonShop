--!strict
export type UIActions = {
	closeWindow: (windowId: string) -> (),
	closeAllWindow: () -> (),
	openWindow: (windowId: string, ...any) -> (),
	createFrame: (frameName: string, frameParent: GuiBase2d?, ZIndex: number?) -> Frame,
	hasShowingWindow: () -> boolean,
	isWindowShowing: (windowId: string) -> boolean,
}

return {}
