class Order {
  final int? id;
  final String orderCode;
  final String orderCreatedDate;
  final String orderEstimatedDelivery;
  final String orderCargoCompany;
  final int orderAddress;
  final String orderStatus;
  final String? orderDeliveredDate;

  Order({
    this.id,
    required this.orderCode,
    required this.orderCreatedDate,
    required this.orderEstimatedDelivery,
    required this.orderCargoCompany,
    required this.orderAddress,
    required this.orderStatus,
    this.orderDeliveredDate,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'order_code': orderCode,
      'order_created_date': orderCreatedDate,
      'order_estimated_delivery': orderEstimatedDelivery,
      'order_cargo_company': orderCargoCompany,
      'order_address': orderAddress,
      'order_status': orderStatus,
      if (orderDeliveredDate != null) 'order_delivered_date': orderDeliveredDate,
    };
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    print('Order.fromMap called');
    print('order_status value: ${map['order_status']}');
    print('order_delivered_date value: ${map['order_delivered_date']}');
    print('order_delivered_date type: ${map['order_delivered_date']?.runtimeType}');
    
    return Order(
      id: map['id'],
      orderCode: map['order_code'],
      orderCreatedDate: map['order_created_date'],
      orderEstimatedDelivery: map['order_estimated_delivery'],
      orderCargoCompany: map['order_cargo_company'],
      orderAddress: map['order_address'],
      orderStatus: map['order_status'] ?? 'pending',
      orderDeliveredDate: map['order_delivered_date'],
    );
  }
} 