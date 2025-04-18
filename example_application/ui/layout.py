from PyQt5.QtWidgets import QWidget, QVBoxLayout, QPushButton, QTextEdit, QLabel

class MainWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Joke App")
        self.setGeometry(200, 200, 400, 200)

        self.label = QLabel("Click to get a joke:")
        self.button = QPushButton("Get Joke")
        self.output = QTextEdit()
        self.output.setReadOnly(True)

        layout = QVBoxLayout()
        layout.addWidget(self.label)
        layout.addWidget(self.button)
        layout.addWidget(self.output)

        self.setLayout(layout)
