/// Complete REST API v1 Endpoints for NusaCommerce Cloud Multi-Tenant Gateway
/// Matches routes/api.php in NusaCommerce Cloud Laravel 11 Backend.
class ApiEndpoints {
  ApiEndpoints._();

  /// Default base URL pointing to VPS Cloud Server.
  /// Can be overridden dynamically in Login / Settings Screen.
  static const String defaultBaseUrl = 'http://43.159.49.77/api/v1';
  static const String vpsServerUrl = 'http://43.159.49.77/api/v1';
  static const String laragonDomainUrl = 'http://nusacommerce.test/api/v1';

  // 1. Auth & Multi-Store Session
  static const String login = '/auth/login';
  static const String me = '/auth/me';
  static const String switchStore = '/auth/switch-store';
  static const String logout = '/auth/logout';

  // 2. Products, Variants, FEFO Batches, Stock Opname & Categories
  static const String products = '/products';
  static String productDetail(int id) => '/products/$id';
  static String adjustProductStock(int id) => '/products/$id/adjust-stock';
  static const String categories = '/categories';

  // 3. POS Checkout, Hold Cart, Sales History, Refund, Void, Online Orders & Restaurant Tables
  static const String paymentMethods = '/pos/payment-methods';
  static const String returnReasons = '/pos/return-reasons';
  static const String priceCart = '/pos/price-cart';
  static const String checkout = '/pos/checkout';
  static const String holdCart = '/pos/hold';
  static const String heldSales = '/pos/held';
  static const String salesHistory = '/pos/sales';
  static const String verifyPin = '/pos/verify-pin';
  static String saleDetail(int id) => '/pos/sales/$id';
  static String voidSale(int id) => '/pos/sales/$id/void';
  static String refundSale(int id) => '/pos/sales/$id/refund';
  static const String restaurantTables = '/pos/tables';
  static String openTable(int tableId) => '/pos/tables/$tableId/open';
  static String transferTable(int tableId) => '/pos/tables/$tableId/transfer';
  static String splitTable(int tableId) => '/pos/tables/$tableId/split';
  static const String offlineConflicts = '/pos/offline-conflicts';
  static const String onlineOrders = '/online-orders';
  static String updateOnlineOrderStatus(int id) => '/online-orders/$id/status';

  // 4. Cashier Shift & Cash Drawer (Open, Cash Entry, Close Z-Report)
  static const String currentShift = '/shifts/current';
  static const String openShift = '/shifts/open';
  static const String cashEntry = '/shifts/cash-entry';
  static const String closeShift = '/shifts/close';

  // 5. Customers, Suppliers, Quick Stock In & Buku Bon Piutang / Hutang
  static const String customers = '/customers';
  static String customerDetail(int id) => '/customers/$id';
  static const String suppliers = '/suppliers';
  static String supplierDetail(int id) => '/suppliers/$id';
  static const String quickStockIn = '/purchases/quick-stock-in';
  static const String receivables = '/debts/receivables';
  static String payReceivable(int saleId) => '/debts/receivables/$saleId/pay';
  static const String payables = '/debts/payables';
  static String payPayable(int purchaseId) => '/debts/payables/$purchaseId/pay';

  // 6. Operational Store Expenses
  static const String expenses = '/expenses';

  // 7. Executive Owner Command Center, Reports & OS Operations
  static const String ownerDashboard = '/reports/owner-dashboard';
  static const String salesSummary = '/reports/sales-summary';
  static const String approvals = '/approvals';
  static String decideApproval(int id) => '/approvals/$id/decide';
  static const String tasks = '/tasks';
  static const String copilotChat = '/ai/copilot/chat';
}
