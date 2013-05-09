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

    $(document).on("click", "a.bmark-ajax", function(e) {
	console.log("bookmark click!");
	e.preventDefault();
	var href = $(this).attr("href");
	var href_ajax = href.match("\\?") ? href + "&ajax=1" : href + "?ajax=1";
	console.log("href_ajax=" + href);
	$.ajax( href_ajax, { dataType: 'json' } )
	    .done( function( data ) {
		console.log("got data " + data);
		console.log("data.success=" + data.success);
		if ( data.success ) {
		    console.log("success!");
		    console.log("data.html=" + data.html);
		    animateTo("#bmark_bookmarks", data.html, true);
		    history.pushState(null, null, href);
		} else {
		    console.log("no success?");
		}
	    });
    });

    
    $(document).on("click", "button.bmark-post-add", function(e) {
	// FIXME change to post
	console.log("bookmark click!");
	e.preventDefault();
	var href = "/bookmarks/post/add.json";
	var bmarkId =  $(this).data("bmarkid");
	var data = "post_id=" + bmarkId + "&ajax=1";
	console.log("href=" + href);
	$.post( href, data, { dataType: 'json',  } )
	    .done( function( data ) {
		console.log("got data " + data);
		console.log("data.success=" + data.success);
		if ( data.success ) {
		    console.log("success!");
		    animateTo("#bmark_post", data.post, false);
		    animateTo("#bmark_" + bmarkId , data.bmark, false);
		    //history.pushState(null, null, href);
		} else {
		    console.log("no success?");
		}
	    });
    });

    function animateTo( sourceSelector, newHtml, scroll ) {
	console.log("animating..");
	if (scroll) {
	    $('html, body').animate({
		scrollTop: $(sourceSelector).offset().top
	    }, 800);
	}
	$(sourceSelector).fadeOut(800, function() {
            $(this).replaceWith(newHtml);
        });
    }
})(jQuery);

