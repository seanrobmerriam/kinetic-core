from playwright.sync_api import sync_playwright
import json


def check_dashboard():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        console_messages = []
        console_errors = []

        def handle_console(msg):
            console_messages.append({"type": msg.type, "text": msg.text})
            if msg.type == "error":
                console_errors.append(msg.text)

        page.on("console", handle_console)

        try:
            page.goto("http://localhost:8080", timeout=10000)
            page.wait_for_load_state("networkidle", timeout=10000)

            screenshot_path = "/tmp/dashboard_screenshot.png"
            page.screenshot(path=screenshot_path, full_page=True)

            dom_content = page.content()

            print("=== PAGE RENDERING ===")
            print(f"Page title: {page.title()}")
            print(f"URL: {page.url}")

            print("\n=== CONSOLE ERRORS ===")
            if console_errors:
                for err in console_errors:
                    print(f"ERROR: {err}")
            else:
                print("No console errors")

            print("\n=== CONSOLE MESSAGES (all) ===")
            for msg in console_messages:
                print(f"[{msg['type']}] {msg['text']}")

            print("\n=== DOM STRUCTURE (first 3000 chars) ===")
            print(dom_content[:3000])

            print(f"\n=== SCREENSHOT SAVED ===")
            print(f"Path: {screenshot_path}")

        except Exception as e:
            print(f"Error: {e}")

        browser.close()


if __name__ == "__main__":
    check_dashboard()
