import requests
from pydantic import BaseModel

class Joke(BaseModel):
    setup: str
    punchline: str

def get_joke() -> str:
    url = "https://official-joke-api.appspot.com/random_joke"
    response = requests.get(url)
    response.raise_for_status()
    joke = Joke(**response.json())
    return f"{joke.setup}\n\n{joke.punchline}"
