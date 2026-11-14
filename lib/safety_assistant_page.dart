import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'presentation/design_system/design_system.dart';

class SafetyAssistantPage extends StatefulWidget {
  const SafetyAssistantPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  State<SafetyAssistantPage> createState() => _SafetyAssistantPageState();
}

class _SafetyAssistantPageState extends State<SafetyAssistantPage> {
  static const _suggestions = [
    'Summarize the current safety assessment.',
    'What data is missing or needs verification?',
    'What approved action should be taken now?',
  ];

  final _questionController = TextEditingController();
  String? _selectedHelmetId;
  AssistantReply? _reply;
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final helmetId = _selectedHelmetId;
    final question = _questionController.text.trim();
    if (helmetId == null || question.length < 3 || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final reply = await widget.viewModel.dependencies.assistant.ask(
        helmetId: helmetId,
        question: question,
      );
      if (!mounted) return;
      setState(() => _reply = reply);
    } on RepositoryAccessException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error =
            'The safety assistant is temporarily unavailable. Try again.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _useSuggestion(String value) {
    _questionController.text = value;
    _questionController.selection = TextSelection.collapsed(
      offset: value.length,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      final helmets = widget.viewModel.helmets;
      if (helmets.isNotEmpty &&
          !helmets.any((helmet) => helmet.helmetId == _selectedHelmetId)) {
        _selectedHelmetId = helmets.first.helmetId;
      }
      return Column(
        children: [
          AppPageHeader(
            eyebrow: 'DECISION SUPPORT',
            title: 'Safety Assistant',
            subtitle: 'Ask about verified readings and model assessments',
            actions: [
              HeaderIconButton(
                icon: Icons.logout_rounded,
                tooltip: 'Sign out',
                onPressed: widget.onSignOut,
              ),
            ],
          ),
          Expanded(
            child: ContentSheet(
              child: helmets.isEmpty
                  ? const StateView(
                      kind: StateViewKind.empty,
                      title: 'No helmet assigned',
                      message:
                          'An authorized helmet is required before the assistant can explain sensor data.',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        _ContextCard(
                          helmets: helmets,
                          selectedHelmetId: _selectedHelmetId!,
                          onSelected: (value) => setState(() {
                            _selectedHelmetId = value;
                            _reply = null;
                            _error = null;
                          }),
                          assessment: widget.viewModel.assessmentFor(
                            _selectedHelmetId!,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Ask a question',
                                style: AppTypography.subtitle,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Answers use only your authorized helmet data and approved recommendations.',
                                style: AppTypography.body.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  for (final suggestion in _suggestions)
                                    ActionChip(
                                      label: Text(suggestion),
                                      onPressed: _sending
                                          ? null
                                          : () => _useSuggestion(suggestion),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextField(
                                controller: _questionController,
                                enabled: !_sending,
                                minLines: 2,
                                maxLines: 4,
                                maxLength: 500,
                                textInputAction: TextInputAction.newline,
                                decoration: const InputDecoration(
                                  labelText: 'Question',
                                  hintText:
                                      'What does the current assessment mean?',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              AppButton(
                                label: 'Ask assistant',
                                icon: Icons.send_rounded,
                                loading: _sending,
                                onPressed: _sending ? null : _ask,
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          StateView(
                            kind: StateViewKind.error,
                            title: 'Assistant unavailable',
                            message: _error!,
                            onAction: _ask,
                          ),
                        ],
                        if (_reply != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _AssistantAnswer(reply: _reply!),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      );
    },
  );
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.helmets,
    required this.selectedHelmetId,
    required this.onSelected,
    required this.assessment,
  });

  final List<Helmet> helmets;
  final String selectedHelmetId;
  final ValueChanged<String> onSelected;
  final SafetyAssessment? assessment;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Assessment context', style: AppTypography.subtitle),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: selectedHelmetId,
          decoration: const InputDecoration(labelText: 'Helmet'),
          items: [
            for (final helmet in helmets)
              DropdownMenuItem(
                value: helmet.helmetId,
                child: Text(helmet.helmetId),
              ),
          ],
          onChanged: (value) {
            if (value != null) onSelected(value);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          assessment == null
              ? 'No current matching AI assessment is available.'
              : 'Current risk: ${assessment!.overallRisk.name.toUpperCase()} · Event ${assessment!.sourceEventId}',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _AssistantAnswer extends StatelessWidget {
  const _AssistantAnswer({required this.reply});

  final AssistantReply reply;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.support_agent_rounded, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Assistant response', style: AppTypography.subtitle),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableText(
          reply.answer.replaceAll('**', ''),
          style: AppTypography.body.copyWith(height: 1.55),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            reply.disclaimer,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
