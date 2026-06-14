# 🍤 Shrimp Delivery Platform
playstore Download link-https://play.google.com/store/apps/details?id=com.shrimpbite.app&pcampaignid=web_share

**A production-ready, full-stack Flutter application demonstrating advanced mobile development practices, scalable architecture, and seamless real-time integrations.**

---

## 🎯 Overview

This project is a comprehensive clone of a modern seafood/meat delivery platform (like Licious), specifically tailored for a premium shrimp delivery experience. Built with a focus on clean architecture, performance, and user experience, this application serves as a strong technical showcase of modern Flutter capabilities combined with a robust backend infrastructure.

## 🚀 Key Technical Highlights & Achievements

- **Architectural Excellence**: Implemented a scalable, feature-first architecture utilizing **Riverpod** for predictable state management and dependency injection.
- **Real-Time Data Synchronization**: Engineered real-time order tracking and dynamic UI updates using **Socket.io** and **Firebase Cloud Messaging (FCM)**, ensuring a zero-latency experience for end-users.
- **Advanced Location & Mapping**: Integrated **Google Maps**, **Geolocator**, and **Geocoding** APIs to build a robust delivery address resolution and map-based tracking system.
- **Secure Payment Processing**: Integrated **Razorpay** for seamless, secure, and PCI-compliant checkout flows.
- **High-Performance Networking**: Built a resilient API client using **Dio** with interceptors for authentication, error handling, and structured logging via `pretty_dio_logger`.
- **Fluid UI & Micro-interactions**: Delivered a premium user experience utilizing custom animations with `flutter_animate` and intuitive gestures with `flutter_slidable`.

## 🛠 Tech Stack

### Frontend (Mobile App)
- **Framework**: Flutter (v3.0+)
- **State Management**: Riverpod (`flutter_riverpod`, `state_notifier`)
- **Routing/UI Components**: Slidable, Confetti, Pinput (for OTP verification)
- **Animations**: `flutter_animate`

### Backend & Infrastructure
- **Authentication**: Firebase Authentication & Google Sign-In
- **Real-Time Comm**: Socket.IO Client & Firebase Messaging
- **Networking**: Dio
- **Security**: Firebase App Check, `flutter_secure_storage`

### Tools & DevOps
- **Code Generation**: Freezed, JSON Serializable (via `build_runner`)
- **Maps**: Google Maps Flutter

---

## 🏗 Architecture & Design Patterns

The codebase is structured to enforce separation of concerns, making it highly testable and maintainable:

- **Data Layer (`lib/app/data/`)**: Manages remote API calls, socket connections, and local secure storage. Isolates third-party dependencies from business logic.
- **Domain/State Layer**: Utilizes Riverpod providers to manage asynchronous state, caching, and business rules without tightly coupling to the UI.
- **Presentation Layer (`lib/app/ui/`)**: Pure UI components that react to state changes, completely unaware of how the data is fetched or mutated.

Screenshots of the app-

<img width="250" height="600" alt="image" src="https://github.com/user-attachments/assets/9b327be6-d5d4-4acb-aa3d-ee40af75e1f8" />


<img width="300" height="600" alt="image" src="https://github.com/user-attachments/assets/b711fb33-d91f-4f5f-8e09-1ee192cc256d" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/9d20794d-0599-48d4-85ee-56f32283aebb" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/ad6e2a8b-fccf-4558-b298-d7ae294c8ae9" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/08d95256-6379-42f2-b473-d1c046ebcc48" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/6d5722cf-ba47-447a-9f4e-c885343c72d8" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/55669692-dee7-42c5-8bba-3f15b27945ad" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/d64d2793-b818-4e9c-adf4-e7bb16eb9df9" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/98cb8832-6a8a-45cc-8456-0220f840a694" />



<img width="716" height="1600" alt="image" src="https://github.com/user-attachments/assets/020fb926-b505-4a5a-891a-727c431a04e4" />


















## ⚙️ Local Setup & Installation

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 
- Firebase account & project
- Google Cloud Console account (for Maps API)
- Razorpay Dashboard access
