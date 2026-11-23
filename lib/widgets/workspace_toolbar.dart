import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WorkspaceToolbar extends StatelessWidget implements PreferredSizeWidget {
  const WorkspaceToolbar({
    required this.leading,
    required this.actions,
    this.title,
    this.titleBelow = false,
    super.key,
  });

  final Widget leading;
  final List<Widget> actions;
  final Widget? title;
  final bool titleBelow;

  static const _titleHeight = kMinInteractiveDimension;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (titleBelow ? _titleHeight : 0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = title == null
        ? null
        : DefaultTextStyle(
            style: theme.textTheme.titleLarge!,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            child: title!,
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (theme.appBarTheme.systemOverlayStyle ??
              (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark))
          .copyWith(systemNavigationBarColor: theme.scaffoldBackgroundColor),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.orientationOf(context) == Orientation.landscape
                      ? 1120
                      : 680,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: kToolbarHeight,
                    child: Row(
                      children: [
                        leading,
                        if (heading != null && !titleBelow)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: heading,
                            ),
                          )
                        else
                          const Spacer(),
                        ...actions,
                      ],
                    ),
                  ),
                  if (heading != null && titleBelow)
                    SizedBox(
                      height: _titleHeight,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: heading,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
