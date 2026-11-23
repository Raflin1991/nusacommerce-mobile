/// Complete REST API v1 Endpoints for OXO.ID Cloud Multi-Tenant Gateway
/// Matches routes/api.php in OXO.ID Cloud Laravel Backend.
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

  // 2. Products, Variants, FEFO Batches, Stock Opname, Categories, Brands & Units
  static const String products = '/products';
  static String productDetail(int id) => '/products/$id';
  static String adjustProductStock(int id) => '/products/$id/adjust-stock';
  static const String categories = '/categories';
  static String categoryDetail(int id) => '/categories/$id';
  static const String brands = '/brands';
  static String brandDetail(int id) => '/brands/$id';
  static const String units = '/units';
  static String unitDetail(int id) => '/units/$id';

  // 2b. Inventory & Warehouse Operations
  static const String stockMovements = '/inventory/stock-movements';
  static const String inventoryBatches = '/inventory/batches';
  static const String inventoryOversold = '/inventory/oversold';
  static const String adjustmentReasons = '/inventory/adjustment-reasons';
  static const String stockAdjustments = '/inventory/adjustments';
  static const String stockTakes = '/inventory/stock-takes';
  static const String stockTransfers = '/inventory/transfers';
  static String receiveStockTransfer(int id) => '/inventory/transfers/$id/receive';

  // 3. POS Checkout, Hold Cart, Sales History, Refund, Void, Quotations, KDS, Online Orders & F&B Tables
  static const String paymentMethods = '/pos/payment-methods';
  static const String returnReasons = '/pos/return-reasons';
  static String returnReasonDetail(int id) => '/pos/return-reasons/$id';
  static const String kdsQueue = '/pos/kds-queue';
  static String updateKdsStatus(int saleId) => '/pos/kds-queue/$saleId/status';
  static const String quotations = '/quotations';
  static String convertQuotation(int id) => '/quotations/$id/convert-to-sale';
  static const String priceCart = '/pos/price-cart';
  static const String checkout = '/pos/checkout';
  static const String holdCart = '/pos/hold';
  static const String heldSales = '/pos/held';
  static const String salesHistory = '/pos/sales';
  static const String verifyPin = '/pos/verify-pin';
  static const String posWarehouseStock = '/pos/warehouse-stock';
  static String saleDetail(int id) => '/pos/sales/$id';
  static String voidSale(int id) => '/pos/sales/$id/void';
  static String refundSale(int id) => '/pos/sales/$id/refund';
  static const String restaurantTables = '/pos/tables';
  static String openTable(int tableId) => '/pos/tables/$tableId/open';
  static String transferTable(int tableId) => '/pos/tables/$tableId/transfer';
  static String splitTable(int tableId) => '/pos/tables/$tableId/split';
  static const String offlineConflicts = '/pos/offline-conflicts';
  static String resolveOfflineConflict(int id) => '/pos/offline-conflicts/$id/resolve';
  static const String onlineOrders = '/online-orders';
  static String updateOnlineOrderStatus(int id) => '/online-orders/$id/status';

  // 4. Cashier Shift & Cash Drawer (Open, Cash Entry, Close Z-Report)
  static const String currentShift = '/shifts/current';
  static const String openShift = '/shifts/open';
  static const String cashEntry = '/shifts/cash-entry';
  static const String closeShift = '/shifts/close';

  // 5. Customers, Groups, Store Credit, Suppliers, Multi-Item Purchases & Buku Bon Piutang / Hutang
  static const String customers = '/customers';
  static String customerDetail(int id) => '/customers/$id';
  static String customerStatement(int id) => '/customers/$id/statement';
  static String customerStoreCreditTopup(int id) => '/customers/$id/store-credit-topup';
  static const String customerGroups = '/customer-groups';
  static String customerGroupDetail(int id) => '/customer-groups/$id';
  static const String suppliers = '/suppliers';
  static String supplierDetail(int id) => '/suppliers/$id';
  static const String purchases = '/purchases';
  static String receivePurchase(int id) => '/purchases/$id/receive';
  static const String quickStockIn = '/purchases/quick-stock-in';
  static const String purchaseAiReorder = '/purchases/ai-reorder';
  static const String purchaseReturns = '/purchase-returns';
  static const String receivables = '/debts/receivables';
  static const String batchPayReceivables = '/debts/receivables/batch-pay';
  static String receivablePayments(int saleId) => '/debts/receivables/$saleId/payments';
  static String payReceivable(int saleId) => '/debts/receivables/$saleId/pay';
  static const String payables = '/debts/payables';
  static const String batchPayPayables = '/debts/payables/batch-pay';
  static String payablePayments(int purchaseId) => '/debts/payables/$purchaseId/payments';
  static String payPayable(int purchaseId) => '/debts/payables/$purchaseId/pay';

  // 6. Operational Store Expenses & Cash Ledger (Buku Kas)
  static const String expenses = '/expenses';
  static String expenseDetail(int id) => '/expenses/$id';
  static const String expenseCategories = '/expense-categories';
  static String expenseCategoryDetail(int id) => '/expense-categories/$id';
  static const String cashLedger = '/cash-ledger';

  // 7. Executive Owner Command Center, Extended Reports & OS Operations
  static const String ownerDashboard = '/reports/owner-dashboard';
  static const String salesSummary = '/reports/sales-summary';
  static const String reportSalesBreakdown = '/reports/sales-breakdown';
  static const String reportInventoryAnalytics = '/reports/inventory-analytics';
  static const String reportCrmAndPurchases = '/reports/crm-and-purchases';
  static const String reportCashAndExpenses = '/reports/cash-and-expenses';
  static const String reportEnterpriseCompliance = '/reports/enterprise-compliance';
  static const String reportCatalog = '/reports/catalog';
  static String reportRun(String reportId) => '/reports/run/$reportId';
  static String reportExport(String reportId) => '/reports/export/$reportId';
  static const String approvals = '/approvals';
  static String decideApproval(int id) => '/approvals/$id/decide';
  static const String tasks = '/tasks';
  static String toggleTask(int id) => '/tasks/$id/toggle';
  static const String copilotChat = '/ai/copilot/chat';

  // 8. HRD & Attendance
  static const String hrSummary = '/hr/summary';
  static const String hrEmployees = '/hr/employees';
  static const String hrClock = '/hr/attendance/clock';

  // 9. Autonomous Branch Edge (OXO Edge LAN & Cloud Sync)
  static const String edgeHealth = '/edge/health';
  static const String edgeHeartbeat = '/edge/lease/heartbeat';
  static const String edgeSyncPush = '/edge/sync/push';
  static const String edgeSyncPull = '/edge/sync/pull';
  static const String edgeOfflineRenew = '/edge/license/offline-renew';
}
