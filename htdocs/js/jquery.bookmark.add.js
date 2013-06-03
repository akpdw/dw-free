(function($) {
    /**
     * This overrides any a tags identified with the 'dwb' data attribute.
     */
    $(document).on("click", "a[data-dwb='1']", function(e) {
        // we have to build the url by hand for ajax...
        var jqThis=$(this);
        var url = "/bookmarks/new?fragment=1&type=" + jqThis.data("dwb-type") + "&journalname=" + jqThis.data("dwb-journal") + "&ditemid=" + jqThis.data("dwb-ditemid") + "&title=" + jqThis.data("dwb-subject");
        console.log("url=" + url);
        // FIXME -- need to show some kind of busy notification
        dialog = $('<div style="display:none;"></div>').appendTo('body');
        // open the dialog
        dialog.dialog({
            close: function(event, ui) {
                // on close remove the div.
                dialog.remove();
            },
            width: '75%',
            modal: true
        });
        // load remote content
        console.log("loading...");
        dialog.load(
            url,
            function (responseText, textStatus, XMLHttpRequest) {
                // remove the loading class
                dialog.removeClass('loading');
                console.log("loaded...");
            }
        );
        //prevent the browser to follow the link
        e.stopPropagation();
        e.preventDefault();
        return false;
    });
})(jQuery);

