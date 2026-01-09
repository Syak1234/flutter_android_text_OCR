# Flutter Text OCR 🚀

A premium, high-performance Flutter application for real-time Text Recognition (OCR) using Google ML Kit. Designed with a modern, glassmorphic UI and robust state management.

## 🌟 Key Features

- **Live Camera Scanning**: Instant text extraction from the live camera viewfinder.
- **Gallery Extraction**: Pick images from your device gallery to recognize text.
- **Modern UI/UX**: Beautiful glassmorphic design, smooth animations, and a dark-themed aesthetic.
- **Local Scan History**: Automatically saves your scans with searchable history.
- **Usage Statistics**: Track your scanning activity (total scans, character counts).
- **Offline Recognition**: Powered by Google ML Kit for fast and reliable text detection.

## 📖 Comprehensive Use Cases

This application is designed to simplify how you interact with physical text. Here are some key ways it can be used:

### 1. Document & Receipt Digitization
*   **Scenario**: You have a pile of paper receipts or physical documents.
*   **Action**: Use the **Live Scan** feature to capture the text instantly.
*   **Benefit**: Convert physical records into digital, searchable text for easy expense tracking or archiving without manual typing.

### 2. Education & Academic Research
*   **Scenario**: You're studying from a physical textbook and need to quote a specific paragraph.
*   **Action**: Align the camera with the text and tap capture.
*   **Benefit**: Quickly copy quotes, definitions, or reference material directly into your digital notes or research papers.

### 3. Quick Data Entry
*   **Scenario**: You see a phone number, email address, or URL on a physical billboard, business card, or flyer.
*   **Action**: Point the camera and extract the text.
*   **Benefit**: Avoid the friction of manual typing and reduce errors when transferring information from the physical world to your mobile device.

### 4. Accessibility & Reading Aid
*   **Scenario**: Assisting individuals with visual impairments or reading difficulties.
*   **Action**: The app extracts text which can then be used with device screen readers.
*   **Benefit**: Provides an easy way to "read" small print, labels, or signs by converting them into digital text.

### 5. Translation Workflow
*   **Scenario**: You are traveling and need to understand a menu, sign, or instruction manual in a foreign language.
*   **Action**: Scan the text and copy it.
*   **Benefit**: Easily paste the extracted text into translation apps like Google Translate for instant understanding.

### 6. Personal Information Management
*   **Scenario**: You want to remember a specific passage from a magazine or a quote from a book.
*   **Action**: Scan and save to your **Local History**.
*   **Benefit**: Your scans are timestamped and searchable, making it easy to retrieve that specific piece of information weeks or months later.

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev)
- **State Management**: [GetX](https://pub.dev/packages/get)
- **OCR Engine**: [Google ML Kit Text Recognition](https://pub.dev/packages/google_mlkit_text_recognition)
- **Local Storage**: [Shared Preferences](https://pub.dev/packages/shared_preferences)
- **Permissions**: [Permission Handler](https://pub.dev/packages/permission_handler)
- **Typography**: [Google Fonts (JetBrains Mono, Inter)](https://fonts.google.com/)

## 🚀 Getting Started

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/Syak1234/flutter_android_text_OCR.git
    ```
2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```
3.  **Run the application**:
    ```bash
    flutter run
    ```

> [!NOTE]
> This app requires Camera and Storage permissions to function correctly. Ensure you grant these permissions when prompted on the first launch.

---
*Created with ❤️ for seamless text extraction.*
