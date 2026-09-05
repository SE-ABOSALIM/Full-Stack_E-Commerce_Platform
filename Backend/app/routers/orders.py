"""Buyer orders, seller order views, and order-link routes."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import app.models as models
import app.schemas as schemas
from app.dependencies import current_seller, current_user, get_db, owned_resource, require_owner

router = APIRouter()


@router.post("/order", response_model=schemas.OrderBase)
def create_order(order_data: dict, db: Session = Depends(get_db), actor=Depends(current_user)):
    if order_data.get('user_id') is not None:
        require_owner(order_data['user_id'], actor)
    owned_resource(db, models.Address, order_data.get('order_address'), actor)
    if order_data.get('card_id') is not None:
        owned_resource(db, models.CreditCard, order_data['card_id'], actor)
    try:

        # Parse dates from DD/MM/YYYY format to datetime objects
        from datetime import datetime

        def parse_date(date_str):
            if isinstance(date_str, str):
                try:
                    return datetime.strptime(date_str, '%d/%m/%Y')
                except ValueError:
                    # Try alternative format if the first one fails
                    try:
                        return datetime.strptime(date_str, '%Y-%m-%d')
                    except ValueError:
                        return datetime.now()  # Fallback to current date
            return date_str

        # Extract order details and payment info
        order_info = {
            'order_code': order_data.get('order_code'),
            'order_created_date': parse_date(order_data.get('order_created_date')),
            'order_estimated_delivery': parse_date(order_data.get('order_estimated_delivery')),
            'order_cargo_company': order_data.get('order_cargo_company'),
            'order_address': order_data.get('order_address'),
            'order_status': 'pending',
            'order_delivered_date': None
        }
        # Eğer sipariş delivered olarak oluşturuluyorsa bugünün tarihi ata
        if order_info['order_status'] == 'delivered':
            order_info['order_delivered_date'] = datetime.now()

        # Eğer kargo şirketi belirtilmemişse, sipariş edilen ürünlerin satıcılarının kargo şirketini kullan
        if not order_info['order_cargo_company']:
            # Sipariş edilen ürünlerin satıcılarını bul
            cart_items = order_data.get('cart_items', [])
            if cart_items:
                # İlk ürünün satıcısının kargo şirketini kullan
                first_product_id = cart_items[0].get('product', {}).get('seller_id')
                if first_product_id:
                    seller = db.query(models.Seller).filter(models.Seller.id == first_product_id).first()
                    if seller and seller.cargo_company:
                        order_info['order_cargo_company'] = seller.cargo_company
                    else:
                        order_info['order_cargo_company'] = "Araskargo"  # Varsayılan
                else:
                    order_info['order_cargo_company'] = "Araskargo"  # Varsayılan
            else:
                order_info['order_cargo_company'] = "Araskargo"  # Varsayılan

        card_id = order_data.get('card_id')
        amount = order_data.get('amount')


        # Transaction başlat
        # The authentication lookup already opened this transaction.

        # Önce siparişi oluştur
        db_order = models.Order(**order_info, user_id=actor.id)
        db.add(db_order)
        db.flush()  # ID'yi almak için flush yap ama commit etme


        # Eğer kart bilgisi verilmişse temel doğrulamalar yap
        if card_id and amount:
            db_card = db.query(models.CreditCard).filter(models.CreditCard.id == card_id).first()
            if not db_card:
                raise HTTPException(status_code=404, detail="Credit card not found")

            # Son kullanma tarihi kontrolü
            from datetime import datetime
            now = datetime.utcnow()
            exp_year = db_card.expiry_year if db_card.expiry_year >= 100 else 2000 + db_card.expiry_year
            exp_date = datetime(exp_year, db_card.expiry_month, 1)
            if exp_date < datetime(now.year, now.month, 1):
                raise HTTPException(status_code=400, detail="Card expired")

            # Gerçek çekim entegrasyonu burada yapılmalı (ödeme sağlayıcısı)
        else:
            pass

        # Transaction'ı commit et
        db.commit()

        # Şimdi seller_orders tablosuna kayıt ekle
        # Bu siparişteki ürünlerin satıcılarını bul ve seller_orders'a ekle

        # Sipariş edilen ürünleri al (users_order tablosundan)
        user_orders = db.query(models.UsersOrder).filter(
            models.UsersOrder.order_id == db_order.id
        ).all()

        # Her ürün için satıcıyı bul ve seller_orders'a ekle
        for user_order in user_orders:
            product = db.query(models.Product).filter(
                models.Product.id == user_order.product_id
            ).first()



        # Return order with proper string formatting for dates
        return schemas.OrderBase(
            id=db_order.id,
            order_code=db_order.order_code,
            order_created_date=db_order.order_created_date.strftime('%Y-%m-%d') if hasattr(db_order.order_created_date, 'strftime') else str(db_order.order_created_date),
            order_estimated_delivery=db_order.order_estimated_delivery.strftime('%Y-%m-%d') if hasattr(db_order.order_estimated_delivery, 'strftime') else str(db_order.order_estimated_delivery),
            order_cargo_company=db_order.order_cargo_company,
            order_address=db_order.order_address,
            order_status=db_order.order_status,
            order_delivered_date=db_order.order_delivered_date.strftime('%Y-%m-%d') if db_order.order_delivered_date and hasattr(db_order.order_delivered_date, 'strftime') else None
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        # Hata durumunda transaction'ı rollback et
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error creating order: {str(e)}")


@router.get("/order", response_model=list[schemas.OrderBase])
def get_orders(db: Session = Depends(get_db), actor=Depends(current_user)):
    orders = db.query(models.Order).filter_by(user_id=actor.id).all()
    result = []
    for order in orders:



        # order_delivered_date'i manuel olarak kontrol et
        delivered_date_str = None
        if order.order_delivered_date:
            if hasattr(order.order_delivered_date, 'strftime'):
                delivered_date_str = order.order_delivered_date.strftime('%Y-%m-%d')
            else:
                delivered_date_str = str(order.order_delivered_date)

        order_data = schemas.OrderBase(
            id=order.id,
            order_code=order.order_code,
            order_created_date=order.order_created_date.strftime('%Y-%m-%d') if order.order_created_date and hasattr(order.order_created_date, 'strftime') else None,
            order_estimated_delivery=order.order_estimated_delivery.strftime('%Y-%m-%d') if order.order_estimated_delivery and hasattr(order.order_estimated_delivery, 'strftime') else None,
            order_cargo_company=order.order_cargo_company,
            order_address=order.order_address,
            order_status=order.order_status,
            order_delivered_date=delivered_date_str
        )


        result.append(order_data)

    return result


@router.put("/order/{order_id}", response_model=schemas.OrderBase)
def update_order(order_id: int, order: schemas.OrderUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.Address, order.order_address, actor)
    existing = db.get(models.Order, order_id)
    if order.order_status != existing.order_status:
        raise HTTPException(403, "Only the fulfilling seller may change order status")
    owned_resource(db, models.Order, order_id, actor)
    db_order = db.query(models.Order).filter(models.Order.id == order_id).first()
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    for key, value in order.dict().items():
        setattr(db_order, key, datetime.fromisoformat(value) if key in ("order_created_date", "order_estimated_delivery") else value)
    db.commit()
    db.refresh(db_order)
    return schemas.OrderBase(
        id=db_order.id,
        order_code=db_order.order_code,
        order_created_date=db_order.order_created_date.strftime('%Y-%m-%d') if hasattr(db_order.order_created_date, 'strftime') else str(db_order.order_created_date),
        order_estimated_delivery=db_order.order_estimated_delivery.strftime('%Y-%m-%d') if hasattr(db_order.order_estimated_delivery, 'strftime') else str(db_order.order_estimated_delivery),
        order_cargo_company=db_order.order_cargo_company,
        order_address=db_order.order_address,
        order_status=db_order.order_status,
        order_delivered_date=db_order.order_delivered_date.strftime('%Y-%m-%d') if db_order.order_delivered_date and hasattr(db_order.order_delivered_date, 'strftime') else None
    )


@router.delete("/order/{order_id}")
def delete_order(order_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.Order, order_id, actor)
    db_order = db.query(models.Order).filter(models.Order.id == order_id).first()
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    db.delete(db_order)
    db.commit()
    return {"ok": True}


@router.post("/users_order", response_model=schemas.UsersOrderBase)
def create_users_order(uo: schemas.UsersOrderCreate, db: Session = Depends(get_db), actor=Depends(current_user)):
    require_owner(uo.user_id, actor)
    owned_resource(db, models.Order, uo.order_id, actor)
    if db.get(models.Product, uo.product_id) is None:
        raise HTTPException(404, "Product not found")
    try:

        db_uo = models.UsersOrder(**uo.dict())

        db.add(db_uo)
        db.commit()
        db.refresh(db_uo)

        return db_uo
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create users_order: {str(e)}")


@router.get("/users_order", response_model=list[schemas.UsersOrderBase])
def get_users_orders(db: Session = Depends(get_db), actor=Depends(current_user)):
    return db.query(models.UsersOrder).filter_by(user_id=actor.id).all()


@router.put("/users_order/{uo_id}", response_model=schemas.UsersOrderBase)
def update_users_order(uo_id: int, uo: schemas.UsersOrderUpdate, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersOrder, uo_id, actor)
    require_owner(uo.user_id, actor)
    owned_resource(db, models.Order, uo.order_id, actor)
    if db.get(models.Product, uo.product_id) is None:
        raise HTTPException(404, "Product not found")
    db_uo = db.query(models.UsersOrder).filter(models.UsersOrder.id == uo_id).first()
    if not db_uo:
        raise HTTPException(status_code=404, detail="UsersOrder not found")
    for key, value in uo.dict().items():
        setattr(db_uo, key, value)
    db.commit()
    db.refresh(db_uo)
    return db_uo


@router.delete("/users_order/{uo_id}")
def delete_users_order(uo_id: int, db: Session = Depends(get_db), actor=Depends(current_user)):
    owned_resource(db, models.UsersOrder, uo_id, actor)
    db_uo = db.query(models.UsersOrder).filter(models.UsersOrder.id == uo_id).first()
    if not db_uo:
        raise HTTPException(status_code=404, detail="UsersOrder not found")
    db.delete(db_uo)
    db.commit()
    return {"ok": True}


@router.get("/seller_orders/{seller_id}", response_model=list[dict])
def get_seller_orders(seller_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcıya ait siparişleri getir - users_order tablosunu kullanarak"""
    owned_resource(db, models.Seller, seller_id, actor, "id")
    try:
        # Bu satıcıya ait ürünlerin ID'lerini al
        seller_products = db.query(models.Product).filter(
            models.Product.seller_id == seller_id
        ).all()

        seller_product_ids = [product.id for product in seller_products]

        if not seller_product_ids:
            return []

        # Bu satıcının ürünlerini içeren siparişleri al
        user_orders = db.query(models.UsersOrder).filter(
            models.UsersOrder.product_id.in_(seller_product_ids)
        ).all()

        result = []
        processed_orders = set()  # Aynı siparişi tekrar eklememek için

        for user_order in user_orders:
            if user_order.order_id in processed_orders:
                continue

            processed_orders.add(user_order.order_id)

            # Sipariş bilgilerini al
            order = db.query(models.Order).filter(
                models.Order.id == user_order.order_id
            ).first()

            if not order:
                continue

            # Kullanıcı bilgilerini al
            user = db.query(models.User).filter(
                models.User.id == user_order.user_id
            ).first()

            if not user:
                continue

            # Adres bilgilerini al
            address = None
            if order.order_address:
                address = db.query(models.Address).filter(
                    models.Address.id == order.order_address
                ).first()

            # Bu siparişteki bu satıcıya ait ürünleri al
            order_products = []
            for uo in db.query(models.UsersOrder).filter(
                models.UsersOrder.order_id == user_order.order_id,
                models.UsersOrder.product_id.in_(seller_product_ids)
            ).all():
                product = db.query(models.Product).filter(
                    models.Product.id == uo.product_id
                ).first()

                if product:
                    order_products.append({
                        "product_id": product.id,
                        "product_name": product.product_name,
                        "product_price": product.product_price,
                        "quantity": getattr(uo, 'quantity', 1),  # quantity alanı yoksa 1 varsay
                        "total_price": getattr(uo, 'price', product.product_price)  # price alanı yoksa product_price varsay
                    })

            result.append({
                "order_id": order.id,
                "order_code": order.order_code,
                "order_created_date": order.order_created_date.strftime('%Y-%m-%d') if hasattr(order.order_created_date, 'strftime') else str(order.order_created_date),
                "order_estimated_delivery": order.order_estimated_delivery.strftime('%Y-%m-%d') if hasattr(order.order_estimated_delivery, 'strftime') else str(order.order_estimated_delivery),
                "order_cargo_company": order.order_cargo_company,
                "status": order.order_status or "pending",  # Gerçek durum
                "user": {
                    "id": user.id,
                    "name_surname": user.name_surname,
                    "email": user.email,
                    "phone_number": user.phone_number
                },
                "address": {
                    "id": address.id if address else None,
                    "city": address.city if address else "",
                    "district": address.district if address else "",
                    "neighbourhood": address.neighbourhood if address else "",
                    "street_name": address.street_name if address else "",
                    "building_number": address.building_number if address else "",
                    "apartment_number": address.apartment_number if address else "",
                    "address_name": address.address_name if address else ""
                } if address else None,
                "products": order_products
            })

        return result

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting seller orders: {str(e)}")


@router.put("/seller_orders/{order_id}/status")
def update_seller_order_status(order_id: int, status: str, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcı sipariş durumunu güncelle - UPDATED"""
    order = db.get(models.Order, order_id)
    if order is None:
        raise HTTPException(404, "Order not found")
    owners = {row[0] for row in db.query(models.Product.seller_id).join(
        models.UsersOrder, models.UsersOrder.product_id == models.Product.id
    ).filter(models.UsersOrder.order_id == order_id).all()}
    # Status is stored on the whole order. Mixed-seller legacy orders cannot safely be changed here.
    if owners != {actor.id}:
        raise HTTPException(403, "Order is not exclusively fulfilled by this seller")
    if status not in {"pending", "processing", "shipped", "delivered", "cancelled"}:
        raise HTTPException(422, "Invalid order status")
    try:

        if not status:
            raise HTTPException(status_code=400, detail="Status is required")

        # Order'ı bul
        order = db.query(models.Order).filter(models.Order.id == order_id).first()

        if not order:
            raise HTTPException(status_code=404, detail=f"Order with ID {order_id} not found")

        # Status'u güncelle
        order.order_status = status

        # Eğer status "delivered" ise teslim tarihini de güncelle
        if status == 'delivered':
            from datetime import datetime
            order.order_delivered_date = datetime.now()

        db.commit()

        return {"message": "Order status updated successfully", "order_id": order_id, "status": status}

    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating order status: {str(e)}")


@router.get("/seller_statistics/{seller_id}")
def get_seller_statistics(seller_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcı istatistiklerini getir"""
    owned_resource(db, models.Seller, seller_id, actor, "id")
    try:
        # Satıcının ürünlerini al
        seller_products = db.query(models.Product).filter(models.Product.seller_id == seller_id).all()
        product_ids = [product.id for product in seller_products]

        # Toplam ürün sayısı
        total_products = len(seller_products)

        # Satıcının siparişlerini al
        seller_orders = []
        if product_ids:
            # Bu satıcının ürünlerini içeren siparişleri bul
            for uo in db.query(models.UsersOrder).filter(
                models.UsersOrder.product_id.in_(product_ids)
            ).all():
                order = db.query(models.Order).filter(models.Order.id == uo.order_id).first()
                if order and order not in seller_orders:
                    seller_orders.append(order)

        # Toplam sipariş sayısı
        total_orders = len(seller_orders)

        # Durum bazında sipariş sayıları
        pending_orders = len([o for o in seller_orders if o.order_status == 'pending'])
        processing_orders = len([o for o in seller_orders if o.order_status == 'processing'])
        shipped_orders = len([o for o in seller_orders if o.order_status == 'shipped'])
        delivered_orders = len([o for o in seller_orders if o.order_status == 'delivered'])

        # En çok satın alan müşteri
        customer_orders = {}
        for uo in db.query(models.UsersOrder).filter(
            models.UsersOrder.product_id.in_(product_ids)
        ).all():
            order = db.query(models.Order).filter(models.Order.id == uo.order_id).first()
            if order:
                # Order'ın user_id'sini bul
                user_order = db.query(models.UsersOrder).filter(
                    models.UsersOrder.order_id == order.id
                ).first()
                if user_order:
                    user = db.query(models.User).filter(models.User.id == user_order.user_id).first()
                    if user:
                        customer_name = user.name_surname
                        customer_orders[customer_name] = customer_orders.get(customer_name, 0) + 1

        favorite_customer = max(customer_orders.items(), key=lambda x: x[1]) if customer_orders else ("Henüz müşteri yok", 0)

        # En çok satılan ürün
        product_sales = {}
        for uo in db.query(models.UsersOrder).filter(
            models.UsersOrder.product_id.in_(product_ids)
        ).all():
            product = db.query(models.Product).filter(models.Product.id == uo.product_id).first()
            if product:
                product_sales[product.product_name] = product_sales.get(product.product_name, 0) + 1

        best_selling_product = max(product_sales.items(), key=lambda x: x[1]) if product_sales else ("Henüz satış yok", 0)

        return {
            "total_products": total_products,
            "total_orders": total_orders,
            "pending_orders": pending_orders,
            "processing_orders": processing_orders,
            "shipped_orders": shipped_orders,
            "delivered_orders": delivered_orders,
            "favorite_customer": {
                "name": favorite_customer[0],
                "order_count": favorite_customer[1]
            },
            "best_selling_product": {
                "name": best_selling_product[0],
                "sales_count": best_selling_product[1]
            }
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting seller statistics: {str(e)}")


@router.get("/seller_active_orders/{seller_id}", response_model=list[dict])
def get_seller_active_orders(seller_id: int, db: Session = Depends(get_db), actor=Depends(current_seller)):
    """Satıcının aktif siparişlerini getir (pending, processing, shipped)"""
    owned_resource(db, models.Seller, seller_id, actor, "id")
    try:
        # Satıcının ürünlerini al
        seller_products = db.query(models.Product).filter(models.Product.seller_id == seller_id).all()
        product_ids = [product.id for product in seller_products]

        active_orders = []
        if product_ids:
            # Bu satıcının ürünlerini içeren aktif siparişleri bul
            for uo in db.query(models.UsersOrder).filter(
                models.UsersOrder.product_id.in_(product_ids)
            ).all():
                order = db.query(models.Order).filter(models.Order.id == uo.order_id).first()
                if order and order.order_status in ['pending', 'processing', 'shipped']:
                    # Sipariş zaten eklenmiş mi kontrol et
                    if not any(active_order['order_id'] == order.id for active_order in active_orders):
                        # Kullanıcı bilgilerini al
                        user_order = db.query(models.UsersOrder).filter(
                            models.UsersOrder.order_id == order.id
                        ).first()
                        user = None
                        if user_order:
                            user = db.query(models.User).filter(models.User.id == user_order.user_id).first()

                        # Adres bilgilerini al
                        address = None
                        if order.order_address:
                            address = db.query(models.Address).filter(models.Address.id == order.order_address).first()

                        # Ürün bilgilerini al
                        products = []
                        for uo_product in db.query(models.UsersOrder).filter(models.UsersOrder.order_id == order.id).all():
                            product = db.query(models.Product).filter(models.Product.id == uo_product.product_id).first()
                            if product and product.seller_id == seller_id:  # Sadece bu satıcının ürünlerini ekle
                                products.append({
                                    'product_name': product.product_name,
                                    'quantity': getattr(uo_product, 'quantity', 1),
                                    'total_price': getattr(uo_product, 'total_price', product.product_price)
                                })

                        if products:  # Sadece bu satıcının ürünleri varsa ekle
                            active_orders.append({
                                'order_id': order.id,
                                'order_code': order.order_code,
                                'order_created_date': order.order_created_date.strftime('%Y-%m-%d') if order.order_created_date else None,
                                'order_estimated_delivery': order.order_estimated_delivery.strftime('%Y-%m-%d') if order.order_estimated_delivery else None,
                                'order_cargo_company': order.order_cargo_company,
                                'status': order.order_status,
                                'user': {
                                    'name_surname': user.name_surname if user else 'Bilinmeyen',
                                    'email': user.email if user else 'Bilinmeyen',
                                    'phone_number': user.phone_number if user else 'Bilinmeyen'
                                } if user else None,
                                'address': {
                                    'city': address.city if address else 'Bilinmeyen',
                                    'district': address.district if address else 'Bilinmeyen',
                                    'neighbourhood': address.neighbourhood if address else 'Bilinmeyen',
                                    'street_name': address.street_name if address else 'Bilinmeyen',
                                    'building_number': address.building_number if address else 'Bilinmeyen',
                                    'apartment_number': address.apartment_number if address else 'Bilinmeyen'
                                } if address else None,
                                'products': products
                            })

        # Siparişleri tarihe göre sırala (en yeni önce)
        active_orders.sort(key=lambda x: x['order_created_date'] or '', reverse=True)

        return active_orders

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting seller active orders: {str(e)}")
