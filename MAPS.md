# Map markers

OctoGuide uses pfQuest's existing world-map and minimap marker frames. It creates no additional quest pins, numbered checkpoints or route-line overlays. For the current quest, matching start/end/objective metadata is enlarged by 25%. Exact quest IDs and dialog phase are used, including shared map nodes containing several quests.

pfQuest retains control of movement, position, rotation, textures, visibility, tooltips, clicks and mouse-hover animation. Changing quest, disabling emphasis or reusing a frame restores the original size. A hidden or missing pfQuest marker is not recreated by OctoGuide and no pfQuest visibility preference is changed.

Settings control current-marker emphasis and its minimap inclusion. The old route-line/checkpoint settings and handlers have been removed. OctoGuide's guide-window arrow remains separate from map markers.
