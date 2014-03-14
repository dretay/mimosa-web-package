define(function(require) {
    var ListItemModel = require('sf/models/ListItemModel');

    /**
     * Model to represent an MCIRT service.
     */
    ServiceModel = ListItemModel.extend({
        defaults: {
            id: "",
            name: ""
        }
    });

    return ServiceModel;
});
