import time
try:
    from pynput import mouse
    pos = None
    def on_click(x, y, button, pressed):
        global pos
        if pressed:
            pos = (x, y)
    l = mouse.Listener(on_click=on_click)
    l.start()
    print("Click somewhere within 3 seconds...")
    time.sleep(3)
    print("Last click:", pos)
    l.stop()
except ImportError:
    print("No pynput")
