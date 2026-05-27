import 'package:flutter/cupertino.dart';

import '../widgets/repository_scope.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('設定')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('相機'),
              footer: const Text(
                'Bridge URL 是 host 端 sudoku_vision.host_camera 服務的位址（App 預覽用）。'
                '容器走的是 SUDOKU_STREAM_URL，與 App 預覽各自獨立。',
              ),
              children: [
                CupertinoListTile(
                  title: const Text('Bridge URL'),
                  subtitle: Text(repo.bridgeUrl),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => _editBridgeUrl(context, repo),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('模型'),
              children: [
                CupertinoListTile(
                  title: const Text('Tiny CNN 模型'),
                  subtitle: Text(repo.modelReady ? '已載入' : '未載入'),
                  trailing: CupertinoSwitch(
                    value: repo.modelReady,
                    onChanged: repo.setModelReady,
                  ),
                ),
                CupertinoListTile(
                  title: const Text('低信心門檻'),
                  additionalInfo: const Text('0.85'),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('API'),
              footer: const Text(
                '辨識結果會傳送至此 endpoint 進行求解與驗證。',
              ),
              children: [
                CupertinoListTile(
                  title: const Text('Endpoint'),
                  subtitle: Text(repo.apiEndpoint),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => _editEndpoint(context, repo),
                ),
                CupertinoListTile(
                  title: const Text('測試連線'),
                  subtitle: Text(
                    repo.apiClient == null ? '尚未設定 endpoint' : '打 GET /health',
                  ),
                  trailing: const Icon(
                    CupertinoIcons.wifi,
                    size: 18,
                    color: CupertinoColors.activeBlue,
                  ),
                  onTap: () => _testConnection(context, repo),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('關於'),
              children: const [
                CupertinoListTile(
                  title: Text('版本'),
                  additionalInfo: Text('0.1.0'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection(BuildContext context, repo) async {
    if (repo.apiClient == null) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('未設定 endpoint'),
          content: const Text('請先在「Endpoint」輸入後端網址。'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await repo.pingBackend();
    if (!context.mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(ok ? '連線成功' : '連線失敗'),
        content: Text(
          ok
              ? '${repo.apiEndpoint} 回應正常。'
              : '${repo.apiEndpoint} 無法連到或回應錯誤。',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _editBridgeUrl(BuildContext context, repo) async {
    final controller = TextEditingController(text: repo.bridgeUrl);
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (dialog) {
        return CupertinoAlertDialog(
          title: const Text('Camera bridge URL'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              placeholder: 'http://localhost:8765',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialog).pop(null),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialog).pop(controller.text.trim()),
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    if (value != null && value.isNotEmpty) {
      repo.setBridgeUrl(value);
    }
  }

  Future<void> _editEndpoint(BuildContext context, repo) async {
    final controller = TextEditingController(text: repo.apiEndpoint);
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (dialog) {
        return CupertinoAlertDialog(
          title: const Text('API endpoint'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              placeholder: 'http://localhost:8080',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialog).pop(null),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialog).pop(controller.text.trim()),
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    if (value != null && value.isNotEmpty) {
      repo.setApiEndpoint(value);
    }
  }
}
