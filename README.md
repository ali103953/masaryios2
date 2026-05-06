# مساري iOS — خطوات الرفع على GitHub

## هيكل المشروع
```
Masary.xcodeproj/
  project.pbxproj
Masary/
  MasaryApp.swift
  RootView.swift
  Info.plist
  Assets.xcassets/
    AppIcon.appiconset/
    AccentColor.colorset/
codemagic.yaml
README.md
```

## الخطوات

### 1. احذف كل شيء في الـ repo القديم
في GitHub → repo الخاص بك → احذف كل الملفات

### 2. ارفع هذه الملفات فقط
ارفع محتوى هذا الـ ZIP كما هو

### 3. في Codemagic → Settings
- **App Store Connect**: أضف API Key من appstoreconnect.apple.com
- **Team ID**: من developer.apple.com (XXXXXXXXXX)

### 4. ابدأ البيلد
اختر workflow: `ios-release` → Start new build

## ملاحظة مهمة
في `RootView.swift` السطر الأول من `MasaryWebView`:
```swift
private let urlString = "https://masary-b9727.web.app"
```
غيّره لرابط موقعك الفعلي بعد رفعه على Firebase Hosting.
