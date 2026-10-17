import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const QurtubaApp());
}

bool get cloudReady =>
    supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;

SupabaseClient get db => Supabase.instance.client;

class QurtubaApp extends StatelessWidget {
  const QurtubaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'قرطبة',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087E8B)),
      scaffoldBackgroundColor: const Color(0xFFF5F7F8),
      appBarTheme: const AppBarTheme(centerTitle: true),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    home: const StoreHome(),
  );
}

class StoreHome extends StatefulWidget {
  const StoreHome({super.key});
  @override
  State<StoreHome> createState() => _StoreHomeState();
}

class _StoreHomeState extends State<StoreHome> {
  final search = TextEditingController();
  String? categoryId;
  int refreshKey = 0;

  Future<List<Map<String, dynamic>>> loadCategories() async {
    if (!cloudReady) return [];
    final rows = await db.from('categories').select().eq('is_visible', true).order('sort_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadProducts() async {
    if (!cloudReady) return [];
    var query = db.from('products').select().eq('is_visible', true);
    if (categoryId != null) query = query.eq('category_id', categoryId!);
    final rows = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('قرطبة', style: TextStyle(fontWeight: FontWeight.bold)),
      actions: [
        IconButton(
          tooltip: 'لوحة الإدارة',
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLogin()));
            setState(() => refreshKey++);
          },
          icon: const Icon(Icons.admin_panel_settings_outlined),
        ),
      ],
    ),
    body: Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: () async => setState(() => refreshKey++),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF075E68), Color(0xFF10A3A8)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('أهلاً بكم في قرطبة', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text('تصفّح المنتجات واحجز ما تحتاجه من المحل.', style: TextStyle(color: Colors.white)),
              ]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: search,
              onChanged: (_) => setState(() => refreshKey++),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن منتج...'),
            ),
            const SizedBox(height: 16),
            const Text('الأقسام', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey('cats$refreshKey'),
              future: loadCategories(),
              builder: (context, snap) {
                if (snap.hasError) return const Text('تعذر تحميل الأقسام. تحقق من الاتصال والإعدادات.');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final categories = snap.data!;
                if (categories.isEmpty) return const EmptyHint(text: 'سيتم إضافة الأقسام قريباً');
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(label: const Text('الكل'), selected: categoryId == null,
                    onSelected: (_) => setState(() { categoryId = null; refreshKey++; })),
                  ...categories.map((c) => ChoiceChip(
                    label: Text('${c['name']}'),
                    selected: categoryId == c['id'],
                    onSelected: (_) => setState(() { categoryId = c['id'].toString(); refreshKey++; }),
                  )),
                ]);
              },
            ),
            const SizedBox(height: 18),
            const Text('المنتجات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey('products$refreshKey'),
              future: loadProducts(),
              builder: (context, snap) {
                if (!cloudReady) return const EmptyHint(text: 'التطبيق جاهز، لكن يلزم إعداد الاتصال السحابي لعرض بيانات المتجر.');
                if (snap.hasError) return const EmptyHint(text: 'تعذر تحميل المنتجات حالياً.');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final q = search.text.trim().toLowerCase();
                final products = snap.data!.where((p) =>
                  '${p['name']}'.toLowerCase().contains(q) ||
                  '${p['description']}'.toLowerCase().contains(q)).toList();
                if (products.isEmpty) return const EmptyHint(text: 'لا توجد منتجات حالياً. سيتم عرض المنتجات هنا عند إضافتها.');
                return LayoutBuilder(builder: (context, box) {
                  final width = (box.maxWidth - 12) / 2;
                  return Wrap(spacing: 12, runSpacing: 12, children: products.map((p) => SizedBox(
                    width: width,
                    child: ProductCard(product: p, onReserve: () => showReservation(context, p)),
                  )).toList());
                });
              },
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => showAboutDialog(context: context, applicationName: 'قرطبة', children: const [Text('متجر قرطبة — نسخة أولية.')]),
              icon: const Icon(Icons.info_outline), label: const Text('حول التطبيق'),
            ),
          ],
        ),
      ),
    ),
  );
}

class EmptyHint extends StatelessWidget {
  final String text;
  const EmptyHint({super.key, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
  );
}

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onReserve;
  const ProductCard({super.key, required this.product, required this.onReserve});
  @override
  Widget build(BuildContext context) {
    final image = product['image_url']?.toString() ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(aspectRatio: 1.2, child: image.isEmpty
          ? const ColoredBox(color: Color(0xFFE5ECEE), child: Icon(Icons.inventory_2_outlined, size: 42))
          : Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))),
        Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${product['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('${product['price']} ل.س / ${product['unit'] ?? 'قطعة'}', style: const TextStyle(color: Color(0xFF087E8B), fontWeight: FontWeight.bold)),
          Text((product['is_available'] == true && (product['quantity'] as num? ?? 0) > 0) ? 'متوفر' : 'غير متوفر',
            style: TextStyle(color: (product['is_available'] == true && (product['quantity'] as num? ?? 0) > 0) ? Colors.green : Colors.red)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: (product['is_available'] == true && (product['quantity'] as num? ?? 0) > 0) ? onReserve : null,
            child: const Text('احجز الآن'))),
        ])),
      ]),
    );
  }
}

Future<void> showReservation(BuildContext context, Map<String, dynamic> p) async {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final qty = TextEditingController(text: '1');
  await showDialog(context: context, builder: (ctx) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('حجز منتج'),
      content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${p['name']}'),
        const SizedBox(height: 12),
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'الاسم'), validator: (v) => (v == null || v.trim().length < 2) ? 'اكتب الاسم' : null),
        const SizedBox(height: 10),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف'), validator: (v) => (v == null || v.trim().length < 5) ? 'اكتب رقم هاتف صحيحاً' : null),
        const SizedBox(height: 10),
        TextFormField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية'), validator: (v) {
          final n = int.tryParse(v ?? '');
          return n == null || n < 1 ? 'أدخل كمية صحيحة' : null;
        }),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () async {
          if (!form.currentState!.validate()) return;
          if (!cloudReady) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الحجز يحتاج إعداد الاتصال السحابي أولاً.')));
            Navigator.pop(ctx); return;
          }
          try {
            final quantity = int.parse(qty.text);
            if (quantity > (p['quantity'] as num).toInt()) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الكمية المطلوبة أكبر من المتوفر.')));
              return;
            }
            final code = 'QR-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}-${const Uuid().v4().substring(0,4).toUpperCase()}';
            await db.from('orders').insert({
              'order_code': code, 'customer_name': name.text.trim(), 'customer_phone': phone.text.trim(),
              'product_id': p['id'], 'product_name': p['name'], 'quantity': quantity, 'unit_price': p['price'],
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) showDialog(context: context, builder: (c) => AlertDialog(
              title: const Text('تم إرسال الحجز'),
              content: SelectableText('رقم الحجز: $code\nاحتفظ بالرقم لمراجعة المحل.'),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
            ));
          } catch (_) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم ينجح الحجز. حاول مجدداً.')));
          }
        }, child: const Text('تأكيد الحجز')),
      ],
    ),
  ));
}

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}
class _AdminLoginState extends State<AdminLogin> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('دخول الإدارة')),
      body: Padding(padding: const EdgeInsets.all(20), child: !cloudReady
        ? const EmptyHint(text: 'يلزم إعداد الخدمة السحابية أولاً لتفعيل تسجيل الدخول والإدارة.')
        : Column(children: [
          const Icon(Icons.lock_outline, size: 56),
          const SizedBox(height: 16),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
          if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: busy ? null : () async {
              setState(() { busy = true; error = null; });
              try {
                final result = await db.auth.signInWithPassword(email: email.text.trim(), password: password.text);
                final row = await db.from('admins').select('user_id').eq('user_id', result.user!.id).maybeSingle();
                if (row == null) {
                  await db.auth.signOut();
                  throw Exception('هذا الحساب غير مخوّل للإدارة.');
                }
                if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminPanel()));
              } catch (e) {
                setState(() => error = 'تعذر تسجيل الدخول. تحقق من البيانات وصلاحية الإدارة.');
              } finally { if (mounted) setState(() => busy = false); }
            },
            child: Text(busy ? 'جارٍ الدخول...' : 'تسجيل الدخول'),
          )),
        ]),
      ),
    ),
  );
}

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}
class _AdminPanelState extends State<AdminPanel> {
  int tab = 0;
  int refresh = 0;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('إدارة قرطبة'), actions: [
        IconButton(icon: const Icon(Icons.logout), tooltip: 'تسجيل الخروج', onPressed: () async { await db.auth.signOut(); if (context.mounted) Navigator.pop(context); }),
      ]),
      body: IndexedStack(index: tab, children: [
        CategoryAdmin(key: ValueKey('cat$refresh'), changed: () => setState(() => refresh++)),
        ProductAdmin(key: ValueKey('prod$refresh'), changed: () => setState(() => refresh++)),
        OrdersAdmin(key: ValueKey('orders$refresh')),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
        NavigationDestination(icon: Icon(Icons.category_outlined), label: 'الأقسام'),
        NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'المنتجات'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'الحجوزات'),
      ]),
    ),
  );
}

class CategoryAdmin extends StatefulWidget {
  final VoidCallback changed;
  const CategoryAdmin({super.key, required this.changed});
  @override
  State<CategoryAdmin> createState() => _CategoryAdminState();
}
class _CategoryAdminState extends State<CategoryAdmin> {
  Future<List<Map<String, dynamic>>> load() async => List<Map<String, dynamic>>.from(await db.from('categories').select().order('created_at'));
  Future<void> edit([Map<String,dynamic>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final image = TextEditingController(text: item?['image_url']?.toString() ?? '');
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(item == null ? 'إضافة قسم' : 'تعديل قسم'),
      content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم القسم'), validator: (v) => v == null || v.trim().isEmpty ? 'اكتب اسم القسم' : null),
        const SizedBox(height: 8), TextField(controller: image, decoration: const InputDecoration(labelText: 'رابط صورة القسم (اختياري)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('إلغاء')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx,true); }, child: const Text('حفظ'))]));
    if (ok != true) return;
    final values = {'name': name.text.trim(), 'image_url': image.text.trim().isEmpty ? null : image.text.trim()};
    if (item == null) { await db.from('categories').insert(values); } else { await db.from('categories').update(values).eq('id', item['id']); }
    if (mounted) setState(() {}); widget.changed();
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(future: load(), builder: (context,snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.add), label: const Text('قسم جديد')), body: snap.data!.isEmpty ? const EmptyHint(text: 'لا توجد أقسام. اضغط «قسم جديد» للبدء.') : ListView(padding: const EdgeInsets.all(12), children: snap.data!.map((c) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.category)), title: Text('${c['name']}'),
        trailing: Wrap(children: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => edit(c)),
          IconButton(icon: const Icon(Icons.visibility_off_outlined), onPressed: () async { await db.from('categories').update({'is_visible': !(c['is_visible'] == true)}).eq('id',c['id']); setState((){}); widget.changed(); }),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { final yes = await confirmDelete(context, 'حذف القسم؟'); if (yes) { await db.from('categories').delete().eq('id',c['id']); setState((){}); widget.changed(); } }),
        ]),
      ))).toList()));
  });
}

Future<bool> confirmDelete(BuildContext context, String message) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(
  content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(c,false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c,true), child: const Text('حذف'))])) ?? false;

class ProductAdmin extends StatefulWidget {
  final VoidCallback changed;
  const ProductAdmin({super.key, required this.changed});
  @override
  State<ProductAdmin> createState() => _ProductAdminState();
}
class _ProductAdminState extends State<ProductAdmin> {
  Future<List<Map<String,dynamic>>> load() async => List<Map<String,dynamic>>.from(await db.from('products').select('*, categories(name)').order('created_at', ascending: false));
  Future<void> edit([Map<String,dynamic>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final desc = TextEditingController(text: item?['description']?.toString() ?? '');
    final specs = TextEditingController(text: item?['specifications']?.toString() ?? '');
    final price = TextEditingController(text: item?['price']?.toString() ?? '0');
    final qty = TextEditingController(text: item?['quantity']?.toString() ?? '0');
    final unit = TextEditingController(text: item?['unit']?.toString() ?? 'قطعة');
    final image = TextEditingController(text: item?['image_url']?.toString() ?? '');
    String? category = item?['category_id']?.toString();
    bool available = item?['is_available'] != false;
    final categories = List<Map<String,dynamic>>.from(await db.from('categories').select('id,name').order('name'));
    final form = GlobalKey<FormState>();
    final picker = ImagePicker();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: Text(item == null ? 'إضافة منتج' : 'تعديل منتج'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنتج'), validator: (v) => v == null || v.trim().isEmpty ? 'اكتب الاسم' : null),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: categories.any((c) => c['id'].toString() == category) ? category : null,
          decoration: const InputDecoration(labelText: 'القسم (اختياري)'), items: categories.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text('${c['name']}'))).toList(),
          onChanged: (v) => setD(() => category = v)),
        const SizedBox(height: 8), TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'الوصف')),
        const SizedBox(height: 8), TextFormField(controller: specs, decoration: const InputDecoration(labelText: 'المواصفات')),
        const SizedBox(height: 8), TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر'), validator: (v) => double.tryParse(v ?? '') == null ? 'سعر غير صالح' : null),
        const SizedBox(height: 8), TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'وحدة البيع')),
        const SizedBox(height: 8), TextFormField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية'), validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'كمية غير صالحة' : null),
        const SizedBox(height: 8), TextField(controller: image, decoration: const InputDecoration(labelText: 'رابط الصورة أو ارفع صورة')),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(icon: const Icon(Icons.upload_file), label: const Text('اختيار صورة من الهاتف'), onPressed: () async {
          final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
          if (picked == null) return;
          try {
            final path = '${const Uuid().v4()}_${picked.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
            await db.storage.from('product-images').upload(path, File(picked.path), fileOptions: const FileOptions(upsert: true));
            image.text = db.storage.from('product-images').getPublicUrl(path);
            setD(() {});
          } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل رفع الصورة. تحقق من إعدادات التخزين.'))); }
        })),
        SwitchListTile(value: available, title: const Text('المنتج متوفر'), onChanged: (v) => setD(() => available = v)),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('إلغاء')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx,true); }, child: const Text('حفظ'))],
    )));
    if (ok != true) return;
    final values = {
      'name': name.text.trim(), 'category_id': category, 'description': desc.text.trim(),
      'specifications': specs.text.trim(), 'price': double.parse(price.text), 'unit': unit.text.trim().isEmpty ? 'قطعة' : unit.text.trim(),
      'quantity': int.parse(qty.text), 'image_url': image.text.trim().isEmpty ? null : image.text.trim(),
      'is_available': available,
    };
    if (item == null) { await db.from('products').insert(values); } else { await db.from('products').update(values).eq('id', item['id']); }
    if (mounted) setState(() {}); widget.changed();
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(future: load(), builder: (context,snap) {
    if (snap.hasError) return const EmptyHint(text: 'تعذر تحميل المنتجات.');
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.add), label: const Text('منتج جديد')),
      body: snap.data!.isEmpty ? const EmptyHint(text: 'لا توجد منتجات. اضغط «منتج جديد» للبدء.') : ListView(padding: const EdgeInsets.all(12), children: snap.data!.map((p) => Card(child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined), title: Text('${p['name']}'), subtitle: Text('${p['price']} / ${p['unit']} — الكمية: ${p['quantity']}'),
        trailing: Wrap(children: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => edit(p)),
          IconButton(icon: const Icon(Icons.visibility_off_outlined), onPressed: () async { await db.from('products').update({'is_visible': !(p['is_visible'] == true)}).eq('id',p['id']); setState((){}); widget.changed(); }),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { final yes = await confirmDelete(context, 'حذف المنتج؟ سيبقى اسم المنتج محفوظاً ضمن الحجوزات السابقة.'); if (yes) { await db.from('products').delete().eq('id',p['id']); setState((){}); widget.changed(); } }),
        ]),
      ))).toList()));
  });
}

class OrdersAdmin extends StatefulWidget {
  const OrdersAdmin({super.key});
  @override
  State<OrdersAdmin> createState() => _OrdersAdminState();
}
class _OrdersAdminState extends State<OrdersAdmin> {
  Future<List<Map<String,dynamic>>> load() async => List<Map<String,dynamic>>.from(await db.from('orders').select().order('created_at', ascending: false));
  static const statuses = {'pending':'قيد المراجعة','preparing':'قيد التجهيز','ready':'جاهز للاستلام','completed':'مكتمل','cancelled':'ملغى'};
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(future: load(), builder: (context,snap) {
    if (snap.hasError) return const EmptyHint(text: 'تعذر تحميل الحجوزات.');
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    if (snap.data!.isEmpty) return const EmptyHint(text: 'لا توجد حجوزات حتى الآن.');
    return ListView(padding: const EdgeInsets.all(12), children: snap.data!.map((o) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('رقم الحجز: ${o['order_code']}', style: const TextStyle(fontWeight: FontWeight.bold)),
      Text('الزبون: ${o['customer_name']} — ${o['customer_phone']}'),
      Text('المنتج: ${o['product_name']} × ${o['quantity']}'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: statuses.containsKey(o['status']) ? o['status'] as String : 'pending',
        decoration: const InputDecoration(labelText: 'حالة الحجز'),
        items: statuses.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) async { if (v != null) { await db.from('orders').update({'status':v, 'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('id',o['id']); setState((){}); } }),
    ])))).toList());
  });
}
