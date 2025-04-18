from PyQt5.QtWidgets import QApplication
from ui.layout import MainWindow
from logic.api import get_joke

def main():
    app = QApplication([])

    window = MainWindow()

    def on_click():
        try:
            joke = get_joke()
            window.output.setPlainText(joke)
        except Exception as e:
            window.output.setPlainText(f"Error: {e}")

    window.button.clicked.connect(on_click)
    window.show()

    app.exec_()

# This is the entry point, but the file name is generic
if __name__ == "__main__":
    main()
