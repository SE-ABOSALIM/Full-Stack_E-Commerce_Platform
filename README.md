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
- **FastAPI** REST API
- Pydantic-based request and response validation
- Email and password-based authentication
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

## Future Improvements

Potential future improvements include:

- Stronger backend authorization and ownership enforcement
- Modularization of the backend into smaller services and routers
- Automated test coverage
- Further hardening of payment and checkout workflows
- Advanced analytics and reporting
- Notification services
- Performance optimization
- CI/CD and production deployment configuration

---

## Project Scope
This is a portfolio and learning project developed to model a multi-role e-commerce application and explore full-stack mobile development. The project focuses on implementing interconnected buyer, seller, backend, database, verification, and payment workflows, while leaving room for further architectural, security, testing, and deployment improvements.
