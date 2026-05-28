from setuptools import setup

APP = ['main.py']

OPTIONS = {
    'argv_emulation': False,
    'iconfile': 'icon.icns',
    'packages': ['PyQt6', 'pynput', 'AppKit', 'Foundation', 'objc',
                 'ApplicationServices'],
    'includes': ['store', 'engine', 'editor', 'permissions', 'settings'],
    'plist': {
        'CFBundleName': 'MacroDeck',
        'CFBundleDisplayName': 'MacroDeck',
        'CFBundleIdentifier': 'com.macrodeck.app',
        'CFBundleIconFile': 'icon',
        'CFBundleVersion': '1.0',
        'CFBundleShortVersionString': '1.0',
        'LSUIElement': True,
        'NSAccessibilityUsageDescription':
            'MacroDeck needs Accessibility to play back keystrokes into other apps.',
        'NSAppleEventsUsageDescription':
            'MacroDeck uses Apple Events to send keystrokes to other apps.',
    },
}

setup(
    name='MacroDeck',
    app=APP,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
