@markdown MARKDOWN
    # Header

    * list item 1
    * list item 2
    @for ($.things) |thing| {
    * {{thing.bar}}
    }
    * last item
    * {{$.things.0.bar}}
MARKDOWN
