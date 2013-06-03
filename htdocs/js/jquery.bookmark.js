(function($) {
    
    /* -- utility functions for navigation -- */
    /* Handle an ajaxified post. */
    function ajaxPost( target, form, e, successCallback, errorCallback ) {
        console.log("clicked on submit fragment.");
        e.stopPropagation();
        e.preventDefault();
        console.log("prevented default");

        var data = form.serialize();
        var url = form.attr("action");
        data = data + "&ajax=true";
        console.log("posting.");
        $.post(url, data, { dataType: 'json' }).done(function(result) {
            console.log("result.success=" + result.success);
            if (result.success) {
                successCallback(result);
            } else if ( result.error ) {
                if (errorCallback) {
                        errorCallback(result);
                } else {
                    showAjaxError();
                }
            } else {
                showAjaxError();
            }
        }).fail(function() {
            showAjaxError();
        });
    }
                                                    

    /* Handle an ajaxified link. */
    function ajaxClick( target, e, successCallback ) {
        console.log("link clicked (ajaxClick).");
        e.preventDefault();
        var href = target.attr("href");
        var href_ajax = href.match("\\?") ? href + "&ajax=1" : href + "?ajax=1";
        console.log("href_ajax=" + href);
        console.log("updateTarget= " + target.data("bmark-target"));
        var updateSelector = target.data("bmark-target");
        $.ajax( href_ajax, { dataType: 'json' } )
            .done( function( result ) {
                console.log("got result; result.success=" + result.success);
                if ( result.success ) {
                    console.log("success!");
                    successCallback(result);
                } else if ( result.error ) {
                    // fall back to making the non-ajax request
                    window.location.href = href;
                } else {
                    // fall back to making the non-ajax request
                    window.location.href = href;
                }
            }).fail(function() {
                // fall back to making the non-ajax request
                window.location.href = href;
            });
        
    }

    /* updates the sourceSelector to newHtml and, if scroll is set,
       scrolls it into view. */
    function animateTo( sourceSelector, newHtml, scroll ) {
        console.log("animating..");
        if (scroll && ! isScrolledIntoView($(sourceSelector))) {
            $('html, body').animate({
                scrollTop: $(sourceSelector).offset().top
            }, 300);
        }
        $(sourceSelector).fadeOut(300, function() {
            $(this).replaceWith(newHtml);
        });
    }

    /* checks if the element is currently in the view field */
    function isScrolledIntoView(elem) {
        var docViewTop = $(window).scrollTop();
        var docViewBottom = docViewTop + $(window).height();
        
        var elemTop = $(elem).offset().top;
        var elemBottom = elemTop + $(elem).height();
        
        return ((elemBottom <= docViewBottom) && (elemTop >= docViewTop));
    }

    /* end utility functions for navigation */

    $(document).ready( function() {
        setup_bmark_form( $(document) );
        /*setupBookmarkDialog();
        console.log("checking to see if we need to show the dialog.");
        if ($('span.bmark-target-summary').data("bmark-valid") == "0") {
            console.log("we do; showing.");
            showBookmarkDialog();
        }
        */
    });

    /* autocomplete for tags */
    var dialog;
    function split( val ) {
        return val.split( /,\s*/ );
    }
    function extractLast( term ) {
        return split( term ).pop();
    }
    function setup_bmark_form( jqParentElement ) {
        jqParentElement.find( "input[name='tag_string']" )
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
    }
    /* end autocomplete for tags */
    
    // this overrides the submit tag when we're in a fragment context
    //$('#form').delegate("input[data-dwb-submit='1']", "click", function(e)
    $(document).on("click", "input[data-dwb-submit-fragment='1']", function(e) {
        var target = $(this);
        var replaceTarget = target.data("bmark-target");
        //function ajaxPost( target, form, e, successCallback, errorCallback ) {
        ajaxPost($(this), $(this).parents("form"), e, function(result) {
            if ( replaceTarget ) {
                $(replaceTarget).fadeOut(800, function() {
                    taget.replaceWith(result.html);
                });
                
            }
        }, function(result) {
            //FIXME of course
            alert("error");
        });
        return false;

        /*
        console.log("clicked on submit fragment.");
        e.stopPropagation();
        e.preventDefault();
        console.log("prevented default");

        var replaceTarget = $(this).data("bmark-target");
        var form = $(this).parents("form");
        console.log("got form");
        var data = form.serialize();
        var url = form.attr("action");
        data = data + "&ajax=true";
        console.log("posting.");
        $.post(url, data, { dataType: 'json' }).done(function(result) {
            console.log("posted; got a result.  checking for success. result.success = " + result.success + "; result=" + result);
            if (result.success) {
                console.log("replacing " + replaceTarget);
                if ( replaceTarget ) {
                    $(replaceTarget).fadeOut(800, function() {
                        $(this).replaceWith(result.html);
                    });
                }
            } else {
                // FIXME actually handle response codes
                if (dialog) {
                    dialog.dialog("close");
                    dialog = null;
                } else {
                    console.log("calling window.close()");
                    window.close();
                }
            }
        }).fail(function() {
            alert("error");
        });
        return false;
        */
    });

    // this is all type handling code; ignore for now.

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

    console.log("setting up bmark-ajax click");
    $(document).on("click", "a.bmark-ajax", function(e) {
        var updateSelector = $(this).data("bmark-target");
        var href = $(this).attr("href");
        
        ajaxClick($(this), e, function(result) {
            console.log("success (from ajaxClick)!");
            console.log("animatingto " + updateSelector);
            animateTo(updateSelector, result.html, true);
            history.pushState(null, null, href);
            
        });
        /*
        console.log("bookmark click!");
        e.preventDefault();
        var href = $(this).attr("href");
        var href_ajax = href.match("\\?") ? href + "&ajax=1" : href + "?ajax=1";
        console.log("href_ajax=" + href);
        console.log("updateTarget= " + $(this).data("bmark-target"));
        var updateSelector = $(this).data("bmark-target");
        $.ajax( href_ajax, { dataType: 'json' } )
            .done( function( data ) {
                console.log("got result " + result);
                console.log("result.success=" + result.success);
                if ( result.success ) {
                    console.log("success!");
                    console.log("result.html=" + result.html);
                    //        animateTo("#bmark_bookmarks", result.html, true);
                    console.log("animatingto " + $(this).result("bmark-target"));
                    animateTo(updateSelector, result.html, true);
                    history.pushState(null, null, href);
                } else {
                    console.log("no success?");
                }
            });
            */
    });

    $(document).on("click", "a.bmark-", function(e) {
        var updateSelector = $(this).data("bmark-target");
        var href = $(this).attr("href");
        
        ajaxClick($(this), e, function(result) {
            console.log("success (from ajaxClick)!");
            console.log("animatingto " + updateSelector);
            animateTo(updateSelector, result.html, true);
            history.pushState(null, null, href);
            
        });
        /*
        console.log("bookmark click!");
        e.preventDefault();
        var href = $(this).attr("href");
        var href_ajax = href.match("\\?") ? href + "&ajax=1" : href + "?ajax=1";
        console.log("href_ajax=" + href);
        console.log("updateTarget= " + $(this).data("bmark-target"));
        var updateSelector = $(this).data("bmark-target");
        $.ajax( href_ajax, { dataType: 'json' } )
            .done( function( result ) {
                console.log("got result " + result);
                console.log("result.success=" + result.success);
                if ( result.success ) {
                    console.log("success!");
                    console.log("result.html=" + result.html);
                    //        animateTo("#bmark_bookmarks", result.html, true);
                    console.log("animatingto " + $(this).data("bmark-target"));
                    animateTo(updateSelector, result.html, true);
                    history.pushState(null, null, href);
                } else {
                    console.log("no success?");
                }
            });
            */
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
            .done( function( result ) {
                console.log("got result " + result);
                console.log("result.success=" + result.success);
                if ( result.success ) {
                    console.log("success!");
                    animateTo("#bmark_post", result.post, false);
                    animateTo("#bmark_" + bmarkId , result.bmark, false);
                    //history.pushState(null, null, href);
                } else {
                    console.log("no success?");
                }
            });
    });

    $(document).on("click", "button[name='selectall']", function(e) {
        e.preventDefault();
        $("input[name='bookmark']").attr("checked", true);
    });

    $(document).on("click", "button[name='selectnone']", function(e) {
        e.preventDefault();
        $("input[name='bookmark']").attr("checked", false);
    });

})(jQuery);

