import 'package:flutter/material.dart';
import '../../features/auth/models/auth_session_model.dart';

/// Role-Adaptive Mobile Workspaces (Gelombang 5 — Zero Cognitive Load + Strict RBAC).
enum MobileWorkspaceRole {
  ownerPulse,
  managerDesk,
  posFastLane,
  warehouseWorkbench,
  employeeEss,
}

class MobileNavTabSpec {
  final int index;
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;

  const MobileNavTabSpec({
    required this.index,
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
  });
}

class MobilePrimaryCtaSpec {
  final String label;
  final String shortLabel;
  final IconData icon;
  final String route;

  const MobilePrimaryCtaSpec({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.route,
  });
}

class MobileWorkspaceSpec {
  final MobileWorkspaceRole role;
  final String title;
  final String shortTitle;
  final String subtitle;
  final IconData icon;
  final MobilePrimaryCtaSpec primaryCta;
  final List<MobileNavTabSpec> tabs;

  const MobileWorkspaceSpec({
    required this.role,
    required this.title,
    required this.shortTitle,
    required this.subtitle,
    required this.icon,
    required this.primaryCta,
    required this.tabs,
  });
}

/// Resolves the authorized Role-Adaptive Workspace and enforces RBAC boundaries.
class MobileWorkspaceResolver {
  MobileWorkspaceResolver._();

  /// The 4 lean operational workspaces exposed in the Mobile Owner/Admin switcher.
  /// Heavy HRD/Payroll administration lives exclusively in Cloud Web (`/admin`).
  static const List<MobileWorkspaceRole> operationalWorkspaces = [
    MobileWorkspaceRole.ownerPulse,
    MobileWorkspaceRole.managerDesk,
    MobileWorkspaceRole.posFastLane,
    MobileWorkspaceRole.warehouseWorkbench,
  ];

  /// Strict exact-match allowlist aligned 1:1 with backend
  /// `AuthorizesMobileStoreAccess::isTenantOwnerOrAdmin`.
  /// Prevents departmental admin titles (e.g. "Admin Gudang", "Admin HR", "Admin Kasir")
  /// from escalating to Owner Pulse or switching workspaces.
  static const Set<String> _ownerExactRoles = {
    'admin',
    'administrator',
    'owner',
    'pemilik',
    'pemilik usaha',
    'direktur',
    'super admin',
    'superadmin',
  };

  static final RegExp _hrWordRegex = RegExp(r'\b(hr|hrd|ess)\b');

  static bool _isWarehouseRole(String role) {
    return role.contains('warehouse') ||
        role.contains('gudang') ||
        role.contains('logistik') ||
        role.contains('stock');
  }

  static bool _isHrRole(String role) {
    return _hrWordRegex.hasMatch(role) ||
        role.contains('human resource') ||
        role.contains('personalia') ||
        role.contains('karyawan') ||
        role.contains('employee');
  }

  static bool _isCashierRole(String role) {
    return role.contains('cashier') || role.contains('kasir');
  }

  static bool canSwitchWorkspaces(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    if (session.permissions.contains('*')) return true;
    final role = session.userRole.trim().toLowerCase();
    if (!_ownerExactRoles.contains(role)) return false;
    // Fail-closed: if `isOwner` is false, require explicit tenant-admin governance
    // permissions rather than escalating empty permission arrays.
    return hasAnyPermission(session, const [
      'roles.manage',
      'settings.update_dangerous',
    ]);
  }

  static bool hasAnyPermission(AuthSessionModel session, List<String> keys) {
    if (session.isOwner || session.isLocalTrial) return true;
    if (session.permissions.contains('*')) return true;
    final permSet = session.permissions.map((e) => e.trim().toLowerCase()).toSet();
    for (final k in keys) {
      if (permSet.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  /// Strict server-aligned check for whether this user can view Owner/Financial KPIs.
  static bool canViewOwnerDashboard(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    final role = session.userRole.trim().toLowerCase();
    if (_isCashierRole(role)) return false;
    if (_isWarehouseRole(role)) return false;
    if (_isHrRole(role)) return false;
    return hasAnyPermission(session, const [
      'reports.view_financial',
      'reports.view_sales',
      'accounting.view',
    ]);
  }

  static bool canViewProfit(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'reports.view_financial',
      'accounting.view',
    ]);
  }

  static bool canViewApprovals(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'approvals.view',
      'approvals.decide',
      'warehouse.transfer_approve',
      'hr.payroll_approve',
    ]);
  }

  static bool canViewReceivables(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'customers.view',
      'customers.payments_record',
      'reports.view_financial',
    ]);
  }

  static bool canUsePos(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    final role = session.userRole.trim().toLowerCase();
    if (_isWarehouseRole(role) || _isHrRole(role) || role.contains('auditor')) {
      return false;
    }
    return hasAnyPermission(session, const ['sales.create', 'shifts.open']);
  }

  static bool canViewShifts(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return canUsePos(session) ||
        hasAnyPermission(session, const [
          'shifts.open',
          'shifts.close_own',
          'shifts.close_others',
          'shifts.view_all',
        ]);
  }

  static bool canViewKds(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return canUsePos(session) || hasAnyPermission(session, const ['pos.kds']);
  }

  static bool canViewSalesHistory(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return canUsePos(session) ||
        hasAnyPermission(session, const [
          'sales.view_own',
          'sales.view_all',
          'reports.view_sales',
        ]);
  }

  static bool canManageQuotations(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'quotations.view_own',
      'quotations.view_all',
      'quotations.create',
    ]);
  }

  static bool canViewProducts(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'products.view',
      'products.create',
      'products.update',
    ]);
  }

  static bool canManageCatalogTaxonomies(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'taxonomies.manage',
      'products.create',
      'products.update',
    ]);
  }

  static bool canManageInventory(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'warehouse.view',
      'products.adjust_stock',
      'products.transfer_stock',
      'warehouse.transfer_approve',
      'warehouse.fulfillment_manage',
      'reports.view_inventory',
    ]);
  }

  static bool canManagePurchases(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'purchases.view',
      'purchases.create',
      'purchases.update',
      'purchases.receive',
    ]);
  }

  static bool canManageExpensesOrPayables(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'expenses.view',
      'expenses.create',
      'suppliers.payments_record',
      'accounting.view',
      'reports.view_financial',
    ]);
  }

  static bool canViewCustomers(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'customers.view',
      'customers.create',
      'crm.leads.view',
      'crm.inbox.view',
    ]);
  }

  static bool canViewSuppliers(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'suppliers.view',
      'purchases.view',
      'purchases.create',
    ]);
  }

  static bool canManageOnlineStore(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'commerce.view',
      'commerce.manage',
      'commerce.orders.manage',
    ]);
  }

  static bool canViewCashLedger(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'accounting.view',
      'accounting.petty_cash',
      'reports.view_financial',
      'expenses.view',
    ]);
  }

  static bool canViewHr(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'hr.view',
      'hr.employees.manage',
      'hr.manage_attendances',
      'hr.payroll_view',
      'reports.view_employees',
    ]);
  }

  static bool canManageStoreProfileAndPrinter(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return canUsePos(session) ||
        hasAnyPermission(session, const [
          'settings.view',
          'settings.update',
          'stores.view',
          'terminals.view',
          'hardware.test_print',
          'sales.print_receipt',
        ]);
  }

  /// Strictly aligned 1:1 with backend `ShiftAndDebtController::canRevealOpenShiftTotals`.
  /// Departmental titles like "Warehouse Manager" or "HR Manager" MUST NOT bypass Blind Drop
  /// unless explicitly granted shift-supervision permissions.
  static bool isSupervisorOrAbove(AuthSessionModel session) {
    if (session.isOwner || session.isLocalTrial) return true;
    return hasAnyPermission(session, const [
      'shifts.view_all',
      'shifts.close_others',
      'shifts.acknowledge_variance',
    ]);
  }

  /// Resolves an RBAC-safe center primary CTA for the active workspace and session.
  /// Prevents read-only roles (e.g. Auditor) or non-POS managers from receiving `/pos` CTAs.
  static MobilePrimaryCtaSpec primaryCtaForSession(
    AuthSessionModel session,
    MobileWorkspaceRole workspace,
  ) {
    final defaultCta = specFor(workspace).primaryCta;
    if (session.isOwner || session.isLocalTrial) return defaultCta;

    if (workspace == MobileWorkspaceRole.managerDesk ||
        workspace == MobileWorkspaceRole.ownerPulse) {
      if (canUsePos(session)) return defaultCta;
      if (canViewOwnerDashboard(session)) {
        return const MobilePrimaryCtaSpec(
          label: 'Buka Laporan',
          shortLabel: 'Laporan',
          icon: Icons.analytics_rounded,
          route: '/reports',
        );
      }
      if (canViewCashLedger(session)) {
        return const MobilePrimaryCtaSpec(
          label: 'Buku Kas Toko',
          shortLabel: 'Buku Kas',
          icon: Icons.account_balance_wallet_rounded,
          route: '/cash-ledger',
        );
      }
      if (canManageInventory(session)) {
        return const MobilePrimaryCtaSpec(
          label: 'Scan Opname Stok',
          shortLabel: 'Opname',
          icon: Icons.qr_code_scanner_rounded,
          route: '/inventory-ops?tab=1',
        );
      }
      return const MobilePrimaryCtaSpec(
        label: 'Pengaturan',
        shortLabel: 'Pengaturan',
        icon: Icons.settings_rounded,
        route: '/settings',
      );
    }

    if (workspace == MobileWorkspaceRole.employeeEss) {
      if (canViewApprovals(session)) {
        return const MobilePrimaryCtaSpec(
          label: 'Persetujuan',
          shortLabel: 'Approval',
          icon: Icons.verified_user_outlined,
          route: '/approvals',
        );
      }
      return const MobilePrimaryCtaSpec(
        label: 'Pengaturan',
        shortLabel: 'Pengaturan',
        icon: Icons.settings_rounded,
        route: '/settings',
      );
    }

    return defaultCta;
  }

  /// Resolves the canonical default workspace for any logged-in role.
  static MobileWorkspaceRole resolveDefaultWorkspace(AuthSessionModel session) {
    if (canSwitchWorkspaces(session)) {
      return MobileWorkspaceRole.ownerPulse;
    }

    final role = session.userRole.trim().toLowerCase();

    if (_isWarehouseRole(role)) {
      return MobileWorkspaceRole.warehouseWorkbench;
    }

    if (_isHrRole(role)) {
      return MobileWorkspaceRole.employeeEss;
    }

    if (_isCashierRole(role)) {
      return MobileWorkspaceRole.posFastLane;
    }

    if (role.contains('manager') ||
        role.contains('supervisor') ||
        role.contains('kepala') ||
        role.contains('accountant') ||
        role.contains('akuntan') ||
        role.contains('keuangan') ||
        role.contains('finance') ||
        role.contains('auditor') ||
        role.contains('sales')) {
      return MobileWorkspaceRole.managerDesk;
    }

    // Permission-based fallback if custom role name is used
    if (hasAnyPermission(session, const ['warehouse.view', 'products.adjust_stock']) &&
        !hasAnyPermission(session, const ['sales.create'])) {
      return MobileWorkspaceRole.warehouseWorkbench;
    }
    if (hasAnyPermission(session, const ['hr.view']) &&
        !hasAnyPermission(session, const ['sales.create', 'reports.view_financial'])) {
      return MobileWorkspaceRole.employeeEss;
    }
    if (hasAnyPermission(session, const ['sales.create']) &&
        !hasAnyPermission(session, const ['reports.view_financial', 'approvals.decide'])) {
      return MobileWorkspaceRole.posFastLane;
    }
    return MobileWorkspaceRole.managerDesk;
  }

  /// Returns strictly RBAC-allowed workspaces for this session.
  /// Owner/Admin can switch across the 4 focused operational workspaces (excluding heavy HR/Payroll);
  /// staff roles remain strictly isolated.
  static List<MobileWorkspaceRole> allowedWorkspaces(AuthSessionModel session) {
    if (canSwitchWorkspaces(session)) {
      return operationalWorkspaces;
    }
    return [resolveDefaultWorkspace(session)];
  }

  /// Resolves active workspace respecting RBAC isolation (prevents non-owner escalation).
  static MobileWorkspaceRole sanitizeActiveWorkspace(
    AuthSessionModel session,
    MobileWorkspaceRole? requested,
  ) {
    final allowed = allowedWorkspaces(session);
    if (requested != null && allowed.contains(requested)) {
      return requested;
    }
    return allowed.first;
  }

  static MobileWorkspaceSpec specFor(MobileWorkspaceRole role) {
    switch (role) {
      case MobileWorkspaceRole.ownerPulse:
        return const MobileWorkspaceSpec(
          role: MobileWorkspaceRole.ownerPulse,
          title: 'Owner Pulse',
          shortTitle: 'Owner',
          subtitle: 'Ringkasan omzet, laba, cabang & radar anti-fraud',
          icon: Icons.insights_rounded,
          primaryCta: MobilePrimaryCtaSpec(
            label: 'Buka Kasir POS',
            shortLabel: 'Kasir POS',
            icon: Icons.point_of_sale_rounded,
            route: '/pos',
          ),
          tabs: [
            MobileNavTabSpec(
              index: 0,
              label: 'Beranda',
              activeIcon: Icons.home_rounded,
              inactiveIcon: Icons.home_outlined,
            ),
            MobileNavTabSpec(
              index: 1,
              label: 'Katalog',
              activeIcon: Icons.inventory_2_rounded,
              inactiveIcon: Icons.inventory_2_outlined,
            ),
            MobileNavTabSpec(
              index: 2,
              label: 'Transaksi',
              activeIcon: Icons.receipt_long_rounded,
              inactiveIcon: Icons.receipt_long_outlined,
            ),
            MobileNavTabSpec(
              index: 3,
              label: 'Semua Menu',
              activeIcon: Icons.grid_view_rounded,
              inactiveIcon: Icons.grid_view_outlined,
            ),
          ],
        );

      case MobileWorkspaceRole.managerDesk:
        return const MobileWorkspaceSpec(
          role: MobileWorkspaceRole.managerDesk,
          title: 'Manager Desk',
          shortTitle: 'Manager',
          subtitle: 'Kontrol approval Maker-Checker, shift & operasional cabang',
          icon: Icons.dashboard_customize_rounded,
          primaryCta: MobilePrimaryCtaSpec(
            label: 'Buka Kasir POS',
            shortLabel: 'Kasir POS',
            icon: Icons.point_of_sale_rounded,
            route: '/pos',
          ),
          tabs: [
            MobileNavTabSpec(
              index: 0,
              label: 'Desk',
              activeIcon: Icons.space_dashboard_rounded,
              inactiveIcon: Icons.space_dashboard_outlined,
            ),
            MobileNavTabSpec(
              index: 1,
              label: 'Katalog',
              activeIcon: Icons.inventory_2_rounded,
              inactiveIcon: Icons.inventory_2_outlined,
            ),
            MobileNavTabSpec(
              index: 2,
              label: 'Transaksi',
              activeIcon: Icons.receipt_long_rounded,
              inactiveIcon: Icons.receipt_long_outlined,
            ),
            MobileNavTabSpec(
              index: 3,
              label: 'Semua Menu',
              activeIcon: Icons.grid_view_rounded,
              inactiveIcon: Icons.grid_view_outlined,
            ),
          ],
        );

      case MobileWorkspaceRole.posFastLane:
        return const MobileWorkspaceSpec(
          role: MobileWorkspaceRole.posFastLane,
          title: 'POS Fast-Lane',
          shortTitle: 'Kasir',
          subtitle: 'Jalur cepat kasir, blind drop shift & layanan pelanggan',
          icon: Icons.flash_on_rounded,
          primaryCta: MobilePrimaryCtaSpec(
            label: 'Buka Kasir POS',
            shortLabel: 'Kasir POS',
            icon: Icons.point_of_sale_rounded,
            route: '/pos',
          ),
          tabs: [
            MobileNavTabSpec(
              index: 0,
              label: 'Fast-Lane',
              activeIcon: Icons.bolt_rounded,
              inactiveIcon: Icons.bolt_outlined,
            ),
            MobileNavTabSpec(
              index: 1,
              label: 'Cek Harga',
              activeIcon: Icons.inventory_2_rounded,
              inactiveIcon: Icons.inventory_2_outlined,
            ),
            MobileNavTabSpec(
              index: 2,
              label: 'Riwayat',
              activeIcon: Icons.receipt_long_rounded,
              inactiveIcon: Icons.receipt_long_outlined,
            ),
            MobileNavTabSpec(
              index: 3,
              label: 'Shift Kasir',
              activeIcon: Icons.lock_clock_rounded,
              inactiveIcon: Icons.lock_clock_outlined,
            ),
          ],
        );

      case MobileWorkspaceRole.warehouseWorkbench:
        return const MobileWorkspaceSpec(
          role: MobileWorkspaceRole.warehouseWorkbench,
          title: 'Warehouse Workbench',
          shortTitle: 'Gudang',
          subtitle: 'Opname scanner, batch FEFO, terima PO & transfer gudang',
          icon: Icons.warehouse_rounded,
          primaryCta: MobilePrimaryCtaSpec(
            label: 'Scan Opname Stok',
            shortLabel: 'Opname',
            icon: Icons.qr_code_scanner_rounded,
            route: '/inventory-ops?tab=1',
          ),
          tabs: [
            MobileNavTabSpec(
              index: 0,
              label: 'Gudang',
              activeIcon: Icons.warehouse_rounded,
              inactiveIcon: Icons.warehouse_outlined,
            ),
            MobileNavTabSpec(
              index: 1,
              label: 'Stok SKU',
              activeIcon: Icons.inventory_2_rounded,
              inactiveIcon: Icons.inventory_2_outlined,
            ),
            MobileNavTabSpec(
              index: 2,
              label: 'PO & Retur',
              activeIcon: Icons.local_shipping_rounded,
              inactiveIcon: Icons.local_shipping_outlined,
            ),
            MobileNavTabSpec(
              index: 3,
              label: 'Operasi',
              activeIcon: Icons.swap_horiz_rounded,
              inactiveIcon: Icons.swap_horiz_outlined,
            ),
          ],
        );

      case MobileWorkspaceRole.employeeEss:
        return const MobileWorkspaceSpec(
          role: MobileWorkspaceRole.employeeEss,
          title: 'Portal Staf',
          shortTitle: 'Staf',
          subtitle: 'Tugas cabang & pengaturan akun — HRD/Payroll tersedia di OXORA Cloud Web',
          icon: Icons.badge_rounded,
          primaryCta: MobilePrimaryCtaSpec(
            label: 'Pengaturan',
            shortLabel: 'Pengaturan',
            icon: Icons.settings_rounded,
            route: '/settings',
          ),
          tabs: [
            MobileNavTabSpec(
              index: 0,
              label: 'Beranda',
              activeIcon: Icons.badge_rounded,
              inactiveIcon: Icons.badge_outlined,
            ),
            MobileNavTabSpec(
              index: 1,
              label: 'Cloud Web',
              activeIcon: Icons.public_rounded,
              inactiveIcon: Icons.public_outlined,
            ),
            MobileNavTabSpec(
              index: 2,
              label: 'Pengaturan',
              activeIcon: Icons.settings_rounded,
              inactiveIcon: Icons.settings_outlined,
            ),
            MobileNavTabSpec(
              index: 3,
              label: 'Menu',
              activeIcon: Icons.grid_view_rounded,
              inactiveIcon: Icons.grid_view_outlined,
            ),
          ],
        );
    }
  }
}
