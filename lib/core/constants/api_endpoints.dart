/// Complete REST API v1 Endpoints for NusaCommerce Cloud Multi-Tenant Gateway
/// Matches routes/api.php in NusaCommerce Cloud Laravel 11 Backend.
class ApiEndpoints {
  ApiEndpoints._();

  /// Default base URL for Android Emulator -> Laragon / Artisan Serve.
  /// Can be overridden dynamically in Login / Settings Screen.
  static const String defaultBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String laragonDomainUrl = 'http://nusacommerce.test/api/v1';

  // 1. Auth & Multi-Store Session
  static const String login = '/auth/login';
  static const String me = '/auth/me';
  static const String switchStore = '/auth/switch-store';
  static const String logout = '/auth/logout';

  // 2. Products, Variants, FEFO Batches & Categories
  static const String products = '/products';
  static String productDetail(int id) => '/products/$id';
  static const String categories = '/categories';

  // 3. POS Checkout, Hold Cart, Sales History, Void & Restaurant Tables
  static const String paymentMethods = '/pos/payment-methods';
  static const String priceCart = '/pos/price-cart';
  static const String checkout = '/pos/checkout';
  static const String holdCart = '/pos/hold';
  static const String heldSales = '/pos/held';
  static const String salesHistory = '/pos/sales';
  static String saleDetail(int id) => '/pos/sales/$id';
  static String voidSale(int id) => '/pos/sales/$id/void';
  static const String restaurantTables = '/pos/tables';

  // 4. Cashier Shift & Cash Drawer (Open, Cash Entry, Close Z-Report)
  static const String currentShift = '/shifts/current';
  static const String openShift = '/shifts/open';
  static const String cashEntry = '/shifts/cash-entry';
  static const String closeShift = '/shifts/close';

  // 5. Customers & Buku Bon Piutang (Sacred Free Core)
  static const String customers = '/customers';
  static const String receivables = '/debts/receivables';
  static String payReceivable(int saleId) => '/debts/receivables/$saleId/pay';

  // 6. Operational Store Expenses
  static const String expenses = '/expenses';

  // 7. Executive Owner Command Center & Reports
  static const String ownerDashboard = '/reports/owner-dashboard';
}
