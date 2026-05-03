from pynput import mouse
import time

last_pos = (0, 0)
def on_click(x, y, button, pressed):
    global last_pos
    if pressed:
        last_pos = (x, y)
        print("Clicked at", last_pos)

listener = mouse.Listener(on_click=on_click)
listener.start()
time.sleep(2)
listener.stop()
