export const BreakpointConfig = {
  debounce: 500,
  onResize(win) {
    const { innerWidth: winWidth } = win;
    let breakpoint = "full";
    if (win.innerWidth >= 768) {
      breakpoint = "tablet";
    }
    if (win.innerWidth >= 840) {
      breakpoint = "desktop-sm";
    }
    if (win.innerWidth >= 960) {
      breakpoint = "desktop";
    }
    if (win.innerWidth >= 1020) {
      breakpoint = "full";
    }
    if (win.innerWidth < 768) {
      breakpoint = "mobile";
    }
    return { breakpoint, winWidth };
  },
  breakpoints: {
    mobile: 768,
    desktopSmall: 840,
    desktop: 960,
    full: 1020,
  },
};
