# Full-Stack E-Commerce Platform

A full-stack e-commerce mobile application built with Flutter, FastAPI, and PostgreSQL.
The project implements buyer and seller workflows covering product management, shopping, orders, reviews, account management, verification, and multilingual user interfaces.

---

## Overview

This project models an end-to-end e-commerce experience where buyers and sellers interact through products, orders, reviews, and account-related workflows.

The application combines a Flutter mobile client with a FastAPI REST API and a PostgreSQL relational database. It includes email and phone verification, payment workflows, client- and server-side validation, and support for Turkish, English, and Arabic.

Developed over several months, the project explores a range of interconnected e-commerce workflows and full-stack development concerns.

---

## Screenshots

## 📱 User Experience
<table>
  <tr>
    <td align="center">
      <img src="assets/SS/user_homepage.png" width="220" /><br />
      <b>Home Page</b>
    </td>
    <td align="center">
      <img src="assets/SS/Product_Details.png" width="220" /><br />
      <b>Product Details</b>
    </td>
    <td align="center">
      <img src="assets/SS/user_cart.png" width="220" /><br />
      <b>Cart</b>
    </td>
    <td align="center">
      <img src="assets/SS/User_Profile.png" width="220" /><br />
      <b>User Profile</b>
    </td>
  </tr>
</table>
&nbsp;

## 🛒 Seller Panel
<table>
  <tr>
    <td align="center">
      <img src="assets/SS/Seller_Dashboard.png" width="220" /><br />
      <b>Dashboard & Statistics</b>
    </td>
    <td align="center">
      <img src="assets/SS/seller_products.png" width="220" /><br />
      <b>Product Management</b>
    </td>
    <td align="center">
      <img src="assets/SS/Seller_Orders.png" width="220" /><br />
      <b>Order Management</b>
    </td>
    <td align="center">
      <img src="assets/SS/Seller_Profile.png" width="220" /><br />
      <b>Seller Profile</b>
    </td>
  </tr>
</table>

---

## Tech Stack

### Frontend
- **Flutter** (Dart)
- State management
- Client-side validation
- Multilingual UI support (TR / EN / AR)

### Backend
- **FastAPI** REST API organized into domain-specific routers
- Pydantic-based request and response validation
- HMAC-signed bearer authentication with separate user and seller identities
- Server-side authorization and resource ownership checks
- Shared database/authentication dependencies and account, verification, and file services
- Salted PBKDF2 password hashing
- Buyer and seller application workflows

### Database
- **PostgreSQL**
- Relational schema design
- User, seller, product, order, review, and verification entities
- Foreign-key relationships and database indexing

### Third-Party Services
- **Twilio** for SMS-based phone verification
- **SMTP / Gmail** for email verification
- **iyzico / iyzipay** for payment and card tokenization workflows

---

## Authentication & Validation

- HMAC-SHA256-signed bearer credentials
- Separate user and seller identities with role-specific route dependencies
- Server-side ownership checks for protected account and resource operations
- Salted PBKDF2 password hashing
- Email and phone verification flows
- Server-side request validation with Pydantic
- Client-side form validation and access restrictions for selected flows
- Validation and error handling across key application workflows

---

## Internationalization

The application supports three languages:
- Turkish
- English
- Arabic

Language switching is available within the application, ensuring a localized user experience.

---

## Core Features

### User Features
- User registration and authentication
- Email & phone number verification
- User profile management
- Product browsing and seller-specific store pages
- Order placement and order status tracking
- Product reviews and ratings
- Restricted access to checkout and sensitive pages for unauthenticated users

### Seller Features
- Seller profile management
- Product creation and management
- Viewing product reviews and ratings
- Order status updates
- Sales statistics and order insights

---

## Error Handling

The application includes validation and error handling for common scenarios such as:

- Authentication failures
- Invalid user input
- Verification errors
- Payment-related errors
- Missing or invalid application resources

Relevant errors are surfaced to the client to provide feedback during application flows.

---

## Automated Testing

The backend currently has 92 automated tests covering authentication and role separation, resource ownership, password and verification flows, phone-number normalization, sensitive logging, and the FastAPI route contract.

Run the backend suite from the repository root:

```sh
python -m pytest backend/tests -q
```

---

## Future Improvements

Potential future improvements include:

- Further hardening of payment and checkout workflows
- Advanced analytics and reporting
- Notification services
- Performance optimization
- CI/CD and production deployment configuration

---

## Project Scope
This is a portfolio and learning project developed to model a multi-role e-commerce application and explore full-stack mobile development. The project focuses on interconnected buyer, seller, backend, database, verification, and payment workflows while leaving room for further payment, performance, and deployment improvements.
