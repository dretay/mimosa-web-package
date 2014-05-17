define(function(require) {
    var Backbone = require('backbone');

    /**
     * Model representing an IOC term.
     */
    var IOCTermsModel = Backbone.Model.extend({
        defaults: {
            uuid: "",
            data_type: "",
            source: "",
            text: "",
            text_prefix: "",
            title: ""
        }
    });

    return IOCTermsModel;
});