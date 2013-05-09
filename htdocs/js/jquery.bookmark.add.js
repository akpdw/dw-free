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
        $.post(url, data).done(function(result) {
            console.log
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

    $(document).ready( function() {
        setupBookmarkDialog();
        console.log("checking to see if we need to show the dialog.");
        if ($('span.bmark-target-summary').data("bmark-valid") == "0") {
            console.log("we do; showing.");
            showBookmarkDialog();
        }
    });

    $(document).on("click", "button.bmark-type-change", function(e) {
        console.log("clicked bmark-type-change");
        e.preventDefault();
        showBookmarkDialog();
    });

    function setupBookmarkDialog() {
        console.log("setting up bookmark dialog.");
        // add a div with the form.
        $('<div id="bmarkUrlDialog" class="simple-form bmark-form" style="display: none;"><fieldset><ol><form id="bmarkUrlForm" method="post" action="/bookmarks/new/validate_link.json"></form></ol></fieldset></div>').appendTo($('#content'));
        console.log("appending to content.");
        // move the bmark-link-entry div to the new form
        $("#bmark-link-entry").appendTo($("#bmarkUrlForm"));
        console.log("moved bmark-link-entry");
        // create hidden inputs in the original form for the original values.
        $('<input type="hidden" name="type" value="">').appendTo($('#bmark-add-form'));
        $('<input type="hidden" name="url" value="">').appendTo($('#bmark-add-form'));
        $('<input type="hidden" name="journalname" value="">').appendTo($('#bmark-add-form'));
        $('<input type="hidden" name="ditemid" value="">').appendTo($('#bmark-add-form'));
        $('<input type="hidden" name="comment" value="">').appendTo($('#bmark-add-form'));
        copyDialogFormValues();
        // hide the entry and comment box
        /*
          $("li.bmark-type-url").hide();
          $("li.bmark-type-entry").hide();
          $("li.bmark-type-comment").hide();
          $("li.bmark-type").hide();
        */
    }
    function showBookmarkDialog() {
        console.log("showing bookmark dialog");
        updateSelectedType();
        var bookmarkDialog = $('#bmarkUrlDialog');
        // open the dialog
        bookmarkDialog.dialog({
            appendTo: "#content",
            title: "Bookmark Link", 
            close: function(event, ui) {
                // on close remove the div.
                bookmarkDialog.dialog("close");
            },
            width: '75%',
            modal: true,
            buttons: {
                "Set": function() {
                    console.log("adding...");
                    var form=$("#bmarkUrlForm");
                    var data = form.serialize();
                    var url = form.attr("action");
                    data = data + "&ajax=true";
                    console.log("posting.");
                    $.getJSON(url, data).done(function(response) {
                        console.log("got response " + response);
                        console.log("response.success=" + response.success);
                        if ( response.success ) {
                            copyDialogFormValues();
                            $('span.bmark-target-summary').html(response.summary);
                            if ( response.tags ) {
                                $("#recommendedtags").text("Recommended tags: " + response.tags);
                                $("#recommendedtags").show();
                            } else {
                                $("#recommendedtags").hide();
                            }
                            bookmarkDialog.dialog("close");

                        } else {
                            console.log("no success?");
                        }
                    });
                }, 
                "Cancel": function() {
                    console.log("cancelling...");
                    bookmarkDialog.dialog("close");
                }
            }
        });
    }

    $(document).on("click", "input.bmark_type_radio", function(e) {
        updateSelectedType();
    });
    
    function updateSelectedType() {
        var type = $('#bmarkUrlDialog input[name="type"]:checked').val();
        if ( type == 'url' ) {
            $('li.bmark-type-url').show();
            $('li.bmark-type-entry').hide();
            $('li.bmark-type-comment').hide();
        } else if ( type == 'entry' ) {
            $('li.bmark-type-url').hide();
            $('li.bmark-type-entry').show();
            $('li.bmark-type-comment').hide();
        } else {
            $('li.bmark-type-url').hide();
            $('li.bmark-type-entry').show();
            $('li.bmark-type-comment').show();
        }
    }

    
    function copyDialogFormValues() {
        $.each(['url', 'journalname', 'ditemid', 'comment'], function() {
            console.log('copying name ' + this);
            $('#bmark-add-form input[name="' + this + '"]').val( $('#bmarkUrlDialog input[name="' + this + '"]').val());
        });
        $('#bmark-add-form input[name="type"]').val( $('#bmarkUrlDialog input[name="type"]:checked').val());
    }
})(jQuery);

