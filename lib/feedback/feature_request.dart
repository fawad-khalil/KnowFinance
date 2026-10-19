import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const featureRequestEmail = 'iam.fawad.khalil@gmail.com';

/// Wraps the whole app so a screenshot can be taken of whatever is on screen.
final screenshotBoundaryKey = GlobalKey();

enum RequestType {
  feature('Feature request'),
  improvement('Improvement'),
  bug('Something is wrong');

  const RequestType(this.label);
  final String label;
}

class FeatureRequest {
  const FeatureRequest(this.type, this.title, this.details, this.screenshot);

  final RequestType type;
  final String title;
  final String details;

  /// Null when the user removed the screenshot.
  final File? screenshot;

  String get subject => 'KnowFinance ${type.label}: $title';

  String body({required String screen}) => [
        details.trim().isEmpty ? '(No details given)' : details.trim(),
        '',
        '---',
        'Type: ${type.label}',
        'Screen: $screen',
        'Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'Sent: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
        if (screenshot != null) 'Screenshot attached.',
      ].join('\n');
}

/// Captures the app at device resolution and saves it as a PNG.
Future<File?> captureScreenshot(BuildContext context) async {
  final boundary = screenshotBoundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  final ratio = MediaQuery.devicePixelRatioOf(context);
  final image = await boundary.toImage(pixelRatio: ratio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/knowfinance_${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file;
}

/// Opens the user's mail app with the request filled in. On Android the
/// system shows a chooser of installed mail apps. On iOS this uses Apple
/// Mail, falling back to the share sheet (Gmail, Outlook...) when no Apple
/// Mail account is set up.
Future<void> sendFeatureRequest(FeatureRequest r, {required String screen}) async {
  final body = r.body(screen: screen);
  final files = [if (r.screenshot != null) r.screenshot!.path];
  try {
    await FlutterEmailSender.send(Email(
      subject: r.subject,
      recipients: const [featureRequestEmail],
      body: body,
      attachmentPaths: files,
    ));
  } on FlutterEmailSenderException catch (e) {
    // iPhones without an Apple Mail account can't attach files through
    // mailto:, so hand everything to the share sheet instead.
    if (e is! FlutterEmailSenderNotAvailableException && e is! FlutterEmailSenderUnsupportedFeatureException) rethrow;
    await SharePlus.instance.share(ShareParams(
      subject: r.subject,
      text: 'To: $featureRequestEmail\n\n$body',
      files: [for (final f in files) XFile(f)],
    ));
  }
}

/// The small button shown on every tab. It hides itself while the
/// screenshot is taken so it doesn't appear in it.
class FeatureRequestButton extends StatefulWidget {
  const FeatureRequestButton({super.key, required this.screenName});

  final String Function() screenName;

  @override
  State<FeatureRequestButton> createState() => _FeatureRequestButtonState();
}

class _FeatureRequestButtonState extends State<FeatureRequestButton> {
  var _capturing = false;

  Future<void> _start() async {
    setState(() => _capturing = true);
    await SchedulerBinding.instance.endOfFrame;
    File? shot;
    try {
      if (mounted) shot = await captureScreenshot(context);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
    if (!mounted) return;
    final request = await Navigator.of(context).push<FeatureRequest>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => FeatureRequestForm(screenshot: shot)),
    );
    if (request == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await sendFeatureRequest(request, screen: widget.screenName());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open a mail app: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_capturing) return const SizedBox.shrink();
    return FloatingActionButton.small(
      heroTag: 'feature-request',
      tooltip: 'Request a feature',
      onPressed: _start,
      child: const Icon(Icons.lightbulb_outline),
    );
  }
}

class FeatureRequestForm extends StatefulWidget {
  const FeatureRequestForm({super.key, this.screenshot});

  final File? screenshot;

  @override
  State<FeatureRequestForm> createState() => _FeatureRequestFormState();
}

class _FeatureRequestFormState extends State<FeatureRequestForm> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  var _type = RequestType.feature;
  late var _includeShot = widget.screenshot != null;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      FeatureRequest(_type, _title.text.trim(), _details.text, _includeShot ? widget.screenshot : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request a feature'),
        actions: [TextButton(onPressed: _submit, child: const Text('Next'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<RequestType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: RequestType.feature, label: Text('Feature')),
                ButtonSegment(value: RequestType.improvement, label: Text('Improve')),
                ButtonSegment(value: RequestType.bug, label: Text('Problem')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Add a short title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _details,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details',
                hintText: 'What would you like, and why would it help?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.screenshot != null) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Attach screenshot'),
                value: _includeShot,
                onChanged: (v) => setState(() => _includeShot = v),
              ),
              if (_includeShot)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant)),
                      child: Image.file(widget.screenshot!, height: 320),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              'Next opens your mail app with this addressed to $featureRequestEmail. '
              'You can review it there before sending.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
