import uiautomation as auto
import time

time.sleep(3)
window = auto.WindowControl(searchDepth=1, ClassName='Chrome_WidgetWin_1')
if window.Exists(0):
    print("Found Chrome")
    # Finding the caret? UIAutomation has a TextPattern or Selection
    focus = auto.GetFocusedControl()
    print("Focused:", focus.Name, focus.ControlType)
    if auto.PatternId.TextPattern in focus.GetSupportedPatterns():
        text_pattern = focus.GetTextPattern()
        selections = text_pattern.GetSelection()
        if selections:
            rect = selections[0].GetBoundingRectangles()
            print("Caret Rect:", rect)
    else:
        print("No TextPattern on focused control")

