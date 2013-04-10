(function($) {

    /* autocomplete for tags */
    var dialog;
    function split( val ) {
	return val.split( /,\s*/ );
    }
    function extractLast( term ) {
	return split( term ).pop();
    }
    $(document).ready( function() {
    console.log("input[name='tag_string']=" + $( "input[name='tag_string']" ).size());
    $( "input[name='tag_string']" )
    // don't navigate away from the field on tab when selecting an item
	.bind( "keydown", function( event ) {
	    console.log("keydown");
	    if ( event.keyCode === $.ui.keyCode.TAB &&
		 $( this ).data( "ui-autocomplete" ).menu.active ) {
		event.preventDefault();
	    }
	})
	.autocomplete({
	    source: function( request, response ) {
		console.log("getting source");
		$.getJSON( "/bookmarks/autocomplete/tag.json", {
		    term: extractLast( request.term )
		}, response );
	    },
	    search: function() {
		console.log("searching");
		// custom minLength
		var term = extractLast( this.value );
		if ( term.length < 2 ) {
		    return false;
		}
	    },
	    focus: function() {
		// prevent value inserted on focus
		return false;
	    },
	    select: function( event, ui ) {
		var terms = split( this.value );
		// remove the current input
		terms.pop();
		// add the selected item
		terms.push( ui.item.value );
		// add placeholder to get the comma-and-space at the end
		terms.push( "" );
		this.value = terms.join( ", " );
		return false;
	    },
	    appendTo: ".bmark-form"
	});
    });

    /**
     * This overrides any a tags identified with the 'dwb' data attribute.
     */
    $(document).on("click", "a[data-dwb='1']", function(e) {
	// we have to build the url by hand for ajax...
	var jqThis=$(this);
	var url = "/bookmarks/new?fragment=1&type=" + jqThis.data("dwb-type") + "&journal=" + jqThis.data("dwb-journal") + "&ditemid=" + jqThis.data("dwb-ditemid") + "&title=" + jqThis.data("dwb-subject");
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

  // this overrides the submit tag when we're in a fragment context
  //$('#form').delegate("input[data-dwb-submit='1']", "click", function(e)
    $(document).on("click", "input[data-dwb-submit-fragment='1']", function(e) {
      console.log("clicked on submit fragment.");
      e.stopPropagation();
      e.preventDefault();
	console.log("prevented default");

      var form = $(this).parents("form");
	console.log("got form");
      var data = form.serialize();
      var url = form.attr("action");
      data = data + "&ajax=true";
      console.log("posting.");
	$.post(url, data).done(function() {
          console.log("closing window now?");
          // FIXME actually handle response codes
          if (dialog) {
            dialog.dialog("close");
            dialog = null;
          } else {
            console.log("calling window.close()");
            window.close();
          }
        }).fail(function() {
	    alert("error");
	});
      return false;
    });

    $(document).on("blur", "input[name='url']", function(e) {
	console.log("url blurred");
	var url = $("input[name='url']").val();
	console.log("url=" + url);
	$.ajax( "/bookmarks/recommend_tags.json?url=" + encodeURIComponent(url) )
	    .done( function( data ) {
		console.log("got " + data.tags );
		if ( data.tags ) {
		    $("#recommendedtags").text("Recommended tags: " + data.tags);
		    $("#recommendedtags").show();
		} else {
		    $("#recommendedtags").show();
		}
	    } );
    });

    $(document).ready(function() {
	console.log("hi on ready");
	$("input[type='radio']").click(function() {
            console.log("clicked!");
        });
    });

    $(document).on("click", "a.bmark-ajax", function(e) {
	console.log("bookmark click!");
	e.preventDefault();
	var href = $(this).attr("href");
	href = href.match("\\?") ? href + "&ajax=1" : href + "?ajax=1";
	console.log("href=" + href);
	$.ajax( href, { dataType: 'json' } )
	    .done( function( data ) {
		console.log("got data " + data);
		console.log("data.success=" + data.success);
		if ( data.success ) {
		    console.log("success!");
		    console.log("data.html=" + data.html);
		    //$("#bmark_bookmarks").replaceWith(data.html);
		    animateTo("#bmark_bookmarks", data.html);
		} else {
		    console.log("no success?");
		}
	    });
    });

    function animateTo( sourceSelector, newHtml ) {
	console.log("animating..");
	$(sourceSelector).fadeOut(300, function() {
            $(this).replaceWith(newHtml);
        });
    }
    
})(jQuery);
