"""Project entry point; the canonical implementation lives with the public skill."""
from pathlib import Path
import runpy

_implementation = Path(__file__).resolve().parents[2] / '.agents/skills/roblox-ui-system/scripts/build_screen_layout_guide.py'
globals().update({key: value for key, value in runpy.run_path(str(_implementation)).items()
                  if not key.startswith('__')})

if __name__ == '__main__':
    runpy.run_path(str(_implementation), run_name='__main__')
