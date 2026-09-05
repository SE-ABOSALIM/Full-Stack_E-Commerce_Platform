"""Route-surface regressions for the modular FastAPI application."""

from collections import Counter

from fastapi.routing import APIRoute

EXPECTED_ROUTES = {
    tuple(line.split(" ", 1))
    for line in """
GET /users/me
PUT /users/me
PUT /users/me/password
POST /auth/forgot-password/request
POST /auth/forgot-password/reset
POST /tokenize
POST /charge
POST /products
GET /products
PUT /products/{product_id}
DELETE /products/{product_id}
POST /send-verification-code
POST /verify-phone
POST /users/{user_id}/send-phone-verification
POST /sms/welcome
POST /sms/order-status
POST /sms/promotional
GET /sms/languages
GET /sms/check-sender-id
POST /users
GET /users
PUT /users/{user_id}
DELETE /users/{user_id}
POST /address
GET /address
PUT /address/{address_id}
DELETE /address/{address_id}
POST /credit_card
GET /credit_card
PUT /credit_card/{card_id}
DELETE /credit_card/{card_id}
POST /order
GET /order
PUT /order/{order_id}
DELETE /order/{order_id}
POST /users_address
GET /users_address
PUT /users_address/{ua_id}
DELETE /users_address/{ua_id}
POST /users_credit_card
GET /users_credit_card
PUT /users_credit_card/{ucc_id}
DELETE /users_credit_card/{ucc_id}
GET /sms/balance
POST /users_order
GET /users_order
PUT /users_order/{uo_id}
DELETE /users_order/{uo_id}
POST /upload-image
GET /check-db
GET /
POST /sellers/signup
POST /sellers/login
GET /sellers/profile
GET /sellers/{seller_id}
GET /sellers/{seller_id}/products
PUT /sellers/profile
GET /seller_orders/{seller_id}
PUT /seller_orders/{order_id}/status
GET /seller_statistics/{seller_id}
GET /seller_active_orders/{seller_id}
POST /seller_reviews
GET /seller_reviews
PUT /seller_reviews/{review_id}
DELETE /seller_reviews/{review_id}
POST /send-seller-verification-code
POST /verify-seller-phone
POST /send-email-verification-code
POST /verify-email
POST /send-seller-email-verification-code
POST /verify-seller-email
POST /users/login
POST /users/{user_id}/follow-seller/{seller_id}
DELETE /users/{user_id}/unfollow-seller/{seller_id}
GET /users/{user_id}/followed-sellers
GET /sellers/{seller_id}/followers-count
GET /users/{user_id}/is-following/{seller_id}
POST /sellers/{seller_id}/send-phone-verification
""".strip().splitlines()
}


def api_routes(app):
    return [route for route in app.routes if isinstance(route, APIRoute)]


def route_for(app, method, path):
    return next(
        route
        for route in api_routes(app)
        if route.path == path and method in route.methods
    )


def test_route_inventory_and_router_grouping_are_stable(backend):
    routes = api_routes(backend.app)
    registered = [
        (method, route.path)
        for route in routes
        for method in route.methods
    ]

    assert len(registered) == len(set(registered)) == 78
    assert set(registered) == EXPECTED_ROUTES
    assert Counter(route.endpoint.__module__ for route in routes) == {
        "app.routers.users": 20,
        "app.routers.sellers": 7,
        "app.routers.products": 5,
        "app.routers.orders": 12,
        "app.routers.reviews": 4,
        "app.routers.payments": 10,
        "app.routers.verification": 18,
        "app.routers.system": 2,
    }


def test_openapi_methods_response_models_and_auth_dependencies_are_stable(backend):
    from app import schemas

    document = backend.app.openapi()
    documented = {
        (method.upper(), path)
        for path, operations in document["paths"].items()
        for method in operations
    }
    assert documented == EXPECTED_ROUTES

    assert route_for(backend.app, "POST", "/users").response_model is schemas.UserBase
    assert route_for(backend.app, "POST", "/sellers/signup").response_model is schemas.SellerBase
    assert route_for(backend.app, "POST", "/products").response_model is schemas.ProductBase
    assert route_for(backend.app, "POST", "/tokenize").response_model is schemas.TokenizeCardResponse
    assert route_for(backend.app, "POST", "/seller_reviews").response_model is schemas.SellerReviewBase

    expected_dependencies = {
        ("GET", "/users/me"): ["current_user"],
        ("PUT", "/users/me/password"): ["current_user", "get_db"],
        ("GET", "/sellers/profile"): ["get_db", "current_seller"],
        ("POST", "/products"): ["get_db", "current_seller"],
        ("PUT", "/order/{order_id}"): ["get_db", "current_user"],
        ("PUT", "/seller_reviews/{review_id}"): ["get_db", "current_user"],
        ("POST", "/tokenize"): ["get_db", "current_user"],
        ("POST", "/verify-phone"): ["get_db", "optional_actor"],
        ("POST", "/send-email-verification-code"): ["get_db", "current_user"],
        ("POST", "/sellers/{seller_id}/send-phone-verification"): ["get_db", "current_seller"],
    }
    for key, dependency_names in expected_dependencies.items():
        route = route_for(backend.app, *key)
        assert [dependency.call.__name__ for dependency in route.dependant.dependencies] == dependency_names
