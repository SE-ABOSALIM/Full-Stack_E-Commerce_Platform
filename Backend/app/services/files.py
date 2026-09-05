"""File cleanup helpers shared by product and seller routes."""

import os

import app.models as models


def delete_file_safely(file_path: str, file_type: str = "dosya"):
    """Güvenli dosya silme fonksiyonu"""
    try:
        import os
        if os.path.exists(file_path):
            os.remove(file_path)
            return True
        else:
            return False
    except Exception as e:
        return False


def delete_unreferenced_product_image(db, image_url, product_id):
    # A seller may reuse a public image URL; that does not authorize deleting
    # an image still referenced by another product (or a path outside uploads).
    filename = image_url.rsplit("/", 1)[-1]
    if not filename or "\\" in filename or ":" in filename or filename in (".", ".."):
        return
    other_images = db.query(models.Product.product_image_url).filter(models.Product.id != product_id).all()
    if any(url and url.rsplit("/", 1)[-1] == filename for (url,) in other_images):
        return
    delete_file_safely(os.path.join("uploads", "Product_Image", filename), "Product image")
