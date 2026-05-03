import uiautomation as auto
import time

time.sleep(3)
focus = auto.GetFocusedControl()
print("Focused:", focus.Name, focus.ControlType)
if hasattr(focus, 'GetTextPattern'):
    try:
        tp = focus.GetTextPattern()
        if tp:
            ranges = tp.GetSelection()
            if ranges:
                print("Rects:", ranges[0].GetBoundingRectangles())
    except Exception as e:
        print("Error:", e)
